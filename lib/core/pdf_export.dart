import 'dart:math';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/song.dart';

class _Row {
  final String text;
  final int kind; // 0 header, 1 chord, 2 lyric, 3 blank
  _Row(this.text, this.kind);
  double get units => kind == 0 ? 1.7 : (kind == 3 ? 0.8 : 1.0);
}

/// Resultado do cálculo de encaixe de uma música numa página.
class _Fit {
  final int cols;
  final double font;
  final List<_Row> left, right;
  final bool overflow; // não coube nem na fonte mínima -> deixa fluir p/ +1 página
  _Fit(this.cols, this.font, this.left, this.right, this.overflow);
}

class PdfExport {
  // geometria A4 / tipografia
  static const _pageW = 595.0, _pageH = 842.0;
  static const _margin = 14.0; // margens enxutas p/ caber mais na folha
  static const _gap = 16.0;
  // Métricas reais da JetBrains Mono (ver test/font_metrics_test.dart):
  // avanço 0.60em, extensão vertical dos glifos 1.153em. Cada linha é
  // desenhada com altura fixa `_lineHF`, então a conta de encaixe é exata.
  static const _charWF = 0.60, _lineHF = 1.25;
  // _base: tamanho alvo. _comfort: enquanto 1 coluna render pelo menos isto,
  // não divide — 2 colunas é p/ música grande, não p/ ganhar meio ponto de
  // fonte deixando meia folha vazia. _minFont: abaixo disto desiste de
  // espremer e deixa fluir p/ outra página.
  static const _base = 13.0, _comfort = 9.5, _minFont = 7.5;
  // cabeçalho da música: altura imposta, p/ o espaço restante ser exato
  static const _titleH = 40.0;
  // folga contra arredondamento — a Column do pacote descarta tudo se estourar
  static const _safety = 0.98;

  static String _chordLine(SongLine l) {
    final sorted = [...l.chords]..sort((a, b) => a.idx.compareTo(b.idx));
    final sb = StringBuffer();
    for (final c in sorted) {
      final at = c.idx < 0 ? 0 : c.idx;
      if (sb.length < at) {
        sb.write(' ' * (at - sb.length));
      } else if (sb.isNotEmpty) {
        sb.write(' ');
      }
      sb.write(c.sym);
    }
    return sb.toString();
  }

  /// Uma lista de linhas por seção — o corte de coluna só acontece entre elas.
  static List<List<_Row>> _blocks(Song song) {
    final out = <List<_Row>>[];
    for (var s = 0; s < song.sections.length; s++) {
      final sec = song.sections[s];
      final b = <_Row>[];
      if (s > 0) b.add(_Row('', 3));
      if (sec.name.isNotEmpty) b.add(_Row(sec.name.toUpperCase(), 0));
      for (final l in sec.lines) {
        if (l.chords.isNotEmpty) b.add(_Row(_chordLine(l), 1));
        b.add(_Row(l.lyric.isEmpty ? ' ' : l.lyric, 2));
      }
      out.add(b);
    }
    return out;
  }

  static List<_Row> _rows(Song song) => _blocks(song).expand((b) => b).toList();

  static double _units(List<_Row> rs) => rs.fold<double>(0, (a, r) => a + r.units);

  static int _maxLen(List<_Row> rs) => rs
      .where((r) => r.kind == 1 || r.kind == 2)
      .fold<int>(1, (m, r) => r.text.length > m ? r.text.length : m);

  /// Divide em 2 colunas cortando só em fronteira de seção. Se a divisão ficar
  /// muito desequilibrada (uma seção gigante), cai p/ corte por linha.
  static List<List<_Row>> _split(List<List<_Row>> blocks) {
    final rows = blocks.expand((b) => b).toList();
    final total = _units(rows);
    final half = total / 2;

    double acc = 0, bestDiff = double.infinity;
    var bestBlock = -1;
    for (var i = 0; i < blocks.length - 1; i++) {
      acc += _units(blocks[i]);
      final d = (acc - half).abs();
      if (d < bestDiff) {
        bestDiff = d;
        bestBlock = i + 1;
      }
    }
    if (bestBlock > 0 && bestDiff <= total * 0.35) {
      return [
        blocks.take(bestBlock).expand((b) => b).toList(),
        blocks.skip(bestBlock).expand((b) => b).toList(),
      ];
    }

    acc = 0;
    var split = rows.length;
    for (var i = 0; i < rows.length; i++) {
      acc += rows[i].units;
      if (acc >= half) {
        split = i + 1;
        break;
      }
    }
    return [rows.sublist(0, split), rows.sublist(split)];
  }

  /// Escolhe entre 1 e 2 colunas e a maior fonte que ainda cabe na página.
  static _Fit _fit(Song song, double usableW, double usableH) {
    final blocks = _blocks(song);
    final rows = blocks.expand((b) => b).toList();
    final maxLen = _maxLen(rows);
    final total = _units(rows);

    // 1 coluna
    final f1 = [
      _base,
      usableW / (maxLen * _charWF),
      usableH / (total * _lineHF),
    ].reduce(min);
    // enquanto der p/ ler numa coluna só, fica numa coluna só
    if (f1 >= _comfort) return _Fit(1, f1, rows, const [], false);

    // 2 colunas
    final colW = (usableW - _gap) / 2;
    final parts = _split(blocks);
    final tallest = max(_units(parts[0]), _units(parts[1]));
    final f2 = [
      _base,
      colW / (maxLen * _charWF),
      usableH / (tallest * _lineHF),
    ].reduce(min);

    if (f2 >= _minFont && f2 > f1) {
      return _Fit(2, f2, parts[0], parts[1], false);
    }
    if (f1 >= _minFont) return _Fit(1, f1, rows, const [], false);

    // não cabe numa página nem espremido: melhor ler em duas páginas
    return _Fit(1, _comfort, rows, const [], true);
  }

  static Future<void> printOrShare(Song song,
      {int? colorArgb, String namePrefix = ''}) async {
    final doc = await songDoc(song, colorArgb: colorArgb);
    await Printing.layoutPdf(
        onLayout: (_) => doc.save(), name: '$namePrefix${song.title}.pdf');
  }

  static Future<pw.Document> songDoc(Song song, {int? colorArgb}) async {
    final f = await _fonts();
    final doc = pw.Document();
    _addSongPages(doc, song, f, PdfColor.fromInt(colorArgb ?? 0xFF1A3FB8),
        headerText: song.title);
    return doc;
  }

  /// PDF do repertório: capa (lista numerada) + cada cifra encaixada na página.
  static Future<void> printSetlist(String name, List<Song> songs,
      {int? colorArgb}) async {
    final doc = await setlistDoc(name, songs, colorArgb: colorArgb);
    await Printing.layoutPdf(onLayout: (_) => doc.save(), name: '$name.pdf');
  }

  static Future<pw.Document> setlistDoc(String name, List<Song> songs,
      {int? colorArgb}) async {
    final f = await _fonts();
    final chord = PdfColor.fromInt(colorArgb ?? 0xFF1A3FB8);
    final doc = pw.Document();

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(name,
              style: pw.TextStyle(font: f.bold, fontSize: 26, color: chord)),
          pw.Divider(),
          pw.SizedBox(height: 8),
          ...List.generate(
            songs.length,
            (i) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              child: pw.Text('${i + 1}.  ${songs[i].title}',
                  style: pw.TextStyle(font: f.reg, fontSize: 14)),
            ),
          ),
        ],
      ),
    ));

    for (var i = 0; i < songs.length; i++) {
      _addSongPages(doc, songs[i], f, chord,
          headerText: '${i + 1}. ${songs[i].title}');
    }
    return doc;
  }

  @visibleForTesting
  static List<_Row> debugRows(Song song) => _rows(song);

  @visibleForTesting
  static List<List<_Row>> debugSplit(Song song) => _split(_blocks(song));

  @visibleForTesting
  static const debugBase = _base;

  /// [colunas, fonte, fração da altura útil ocupada] — usado nos testes.
  @visibleForTesting
  static List<double> debugFit(Song song) {
    final usableW = _pageW - 2 * _margin;
    final usableH = (_pageH - 2 * _margin - _titleH) * _safety;
    final f = _fit(song, usableW, usableH);
    final tallest =
        f.cols == 1 ? _units(f.left) : max(_units(f.left), _units(f.right));
    return [
      f.cols.toDouble(),
      f.font,
      tallest * f.font * _lineHF / usableH,
      f.overflow ? 1 : 0,
    ];
  }

  // ---- interno ----

  static Future<_Fonts> _fonts() async => _Fonts(
        pw.Font.ttf(await rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf')),
        pw.Font.ttf(await rootBundle.load('assets/fonts/JetBrainsMono-Bold.ttf')),
      );

  static void _addSongPages(pw.Document doc, Song song, _Fonts f,
      PdfColor chordColor, {required String headerText}) {
    final usableW = _pageW - 2 * _margin;
    final usableH = (_pageH - 2 * _margin - _titleH) * _safety;
    final fit = _fit(song, usableW, usableH);
    final colW = (usableW - _gap) / 2;

    pw.TextStyle styleFor(int kind) {
      switch (kind) {
        case 0:
          return pw.TextStyle(
              font: f.bold, fontSize: fit.font * 0.85, color: chordColor);
        case 1:
          return pw.TextStyle(font: f.bold, fontSize: fit.font, color: chordColor);
        default:
          return pw.TextStyle(font: f.reg, fontSize: fit.font);
      }
    }

    // Altura fixa por linha: pw.Text mede pelo bounding box dos glifos, então
    // linhas sem acento/descendente ficariam mais baixas e o cálculo de
    // encaixe erraria. (Linha em branco também mede zero sem isto.)
    pw.Widget rowWidget(_Row r) => pw.SizedBox(
          height: fit.font * r.units * _lineHF,
          child: r.kind == 3
              ? null
              : pw.Text(r.text,
                  style: styleFor(r.kind), maxLines: 1, softWrap: false),
        );

    pw.Widget colOf(List<_Row> rs) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: rs.map(rowWidget).toList(),
        );

    // altura fixa: pw.Divider e o bbox dos glifos variam, e qualquer estouro
    // faz a Column da página descartar o corpo inteiro
    pw.Widget header() => pw.SizedBox(
          height: _titleH,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                height: 19,
                child: pw.Text(headerText,
                    style: pw.TextStyle(font: f.bold, fontSize: 15)),
              ),
              pw.SizedBox(
                height: 12,
                child: pw.Text(
                  [
                    if (song.artist.isNotEmpty) song.artist,
                    'Tom: ${song.key}',
                    if (song.capo > 0) 'Capo ${song.capo}',
                  ].join('   •   '),
                  style: pw.TextStyle(
                      font: f.reg, fontSize: 9, color: PdfColors.grey700),
                ),
              ),
              pw.Container(height: 0.8, color: PdfColors.grey500),
            ],
          ),
        );

    // não coube nem na fonte mínima: deixa fluir para páginas extras
    if (fit.overflow) {
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(_margin),
        header: (_) => header(),
        build: (_) => _rows(song).map(rowWidget).toList(),
      ));
      return;
    }

    final body = fit.cols == 1
        ? colOf(fit.left)
        : pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(width: colW, child: colOf(fit.left)),
              pw.SizedBox(width: _gap),
              pw.SizedBox(width: colW, child: colOf(fit.right)),
            ],
          );

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(_margin),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [header(), body],
      ),
    ));
  }
}

class _Fonts {
  final pw.Font reg, bold;
  _Fonts(this.reg, this.bold);
}
