import 'dart:math';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/song.dart';
import 'chart_layout.dart';

class PdfExport {
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
  static List<ChartRow> debugRows(Song song) => ChartLayout.rows(song);

  @visibleForTesting
  static List<List<ChartRow>> debugSplit(Song song) =>
      ChartLayout.split(ChartLayout.blocks(song));

  @visibleForTesting
  static List<List<ChartRow>> debugBlocks(Song song) => ChartLayout.blocks(song);

  /// As duas colunas como o layout realmente as montou.
  @visibleForTesting
  static List<List<ChartRow>> debugColumns(Song song) {
    final f = ChartLayout.fit(song, ChartLayout.usableW, ChartLayout.usableH);
    return [f.left, f.right];
  }

  @visibleForTesting
  static const debugBase = ChartLayout.base;

  /// [colunas, fonte, fração da altura útil ocupada, estourou] — p/ testes.
  @visibleForTesting
  static List<double> debugFit(Song song) {
    final f = ChartLayout.fit(song, ChartLayout.usableW, ChartLayout.usableH);
    final tallest = f.cols == 1
        ? ChartLayout.units(f.left)
        : max(ChartLayout.units(f.left), ChartLayout.units(f.right));
    return [
      f.cols.toDouble(),
      f.font,
      tallest * f.font * ChartLayout.lineHF / ChartLayout.usableH,
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
    const usableW = ChartLayout.pageW - 2 * ChartLayout.margin;
    final usableH = ChartLayout.usableH;
    final fit = ChartLayout.fit(song, usableW, usableH);

    // letterSpacing é em pontos: proporcional ao corpo p/ o aperto ser igual
    // em qualquer tamanho, e igual em acorde e letra p/ não desalinhar
    pw.TextStyle styleFor(ChartRow r) {
      switch (r.kind) {
        case 0:
          return pw.TextStyle(
              font: f.bold,
              fontSize: fit.font * 0.85,
              letterSpacing: fit.font * 0.85 * ChartLayout.track,
              color: chordColor);
        case 1:
          return pw.TextStyle(
              font: f.bold,
              fontSize: fit.font,
              letterSpacing: fit.font * ChartLayout.track,
              color: chordColor);
        default:
          // letra do refrão em negrito (mesma largura de caractere, não
          // desalinha os acordes)
          return pw.TextStyle(
              font: r.refrao ? f.bold : f.reg,
              fontSize: fit.font,
              letterSpacing: fit.font * ChartLayout.track);
      }
    }

    // Altura fixa por linha: pw.Text mede pelo bounding box dos glifos, então
    // linhas sem acento/descendente ficariam mais baixas e o cálculo de
    // encaixe erraria. (Linha em branco também mede zero sem isto.)
    pw.Widget rowWidget(ChartRow r) => pw.SizedBox(
          height: fit.font * r.units * ChartLayout.lineHF,
          child: r.kind == 3
              ? null
              : pw.Text(r.text,
                  style: styleFor(r), maxLines: 1, softWrap: false),
        );

    pw.Widget colOf(List<ChartRow> rs) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: rs.map(rowWidget).toList(),
        );

    // altura fixa: pw.Divider e o bbox dos glifos variam, e qualquer estouro
    // faz a Column da página descartar o corpo inteiro
    pw.Widget header() => pw.SizedBox(
          height: ChartLayout.titleH,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                height: 17,
                child: pw.Text(headerText,
                    style: pw.TextStyle(font: f.bold, fontSize: 14)),
              ),
              pw.SizedBox(
                height: 11,
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
        margin: const pw.EdgeInsets.all(ChartLayout.margin),
        header: (_) => header(),
        build: (_) => ChartLayout.rows(song).map(rowWidget).toList(),
      ));
      return;
    }

    final body = fit.cols == 1
        ? colOf(fit.left)
        : pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(width: fit.leftW, child: colOf(fit.left)),
              pw.SizedBox(
                  width: max(ChartLayout.gap, usableW - fit.leftW - fit.rightW)),
              pw.SizedBox(width: fit.rightW, child: colOf(fit.right)),
            ],
          );

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(ChartLayout.margin),
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
