import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/song.dart';

class _Row {
  final String text;
  final int kind; // 0 header, 1 chord, 2 lyric, 3 blank
  _Row(this.text, this.kind);
  double get units => kind == 0 ? 1.7 : (kind == 3 ? 0.6 : 1.0);
}

class PdfExport {
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

  static List<_Row> _rows(Song song) {
    final rows = <_Row>[];
    for (var s = 0; s < song.sections.length; s++) {
      final sec = song.sections[s];
      if (s > 0) rows.add(_Row('', 3));
      if (sec.name.isNotEmpty) rows.add(_Row(sec.name.toUpperCase(), 0));
      for (final l in sec.lines) {
        if (l.chords.isNotEmpty) rows.add(_Row(_chordLine(l), 1));
        rows.add(_Row(l.lyric.isEmpty ? ' ' : l.lyric, 2));
      }
    }
    return rows;
  }

  static Future<void> printOrShare(Song song, {int? colorArgb, String namePrefix = ''}) async {
    final reg = pw.Font.ttf(await rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/JetBrainsMono-Bold.ttf'));
    final chordColor = PdfColor.fromInt(colorArgb ?? 0xFF1A3FB8);

    final rows = _rows(song);
    final maxLen = rows
        .where((r) => r.kind == 1 || r.kind == 2)
        .fold<int>(1, (m, r) => r.text.length > m ? r.text.length : m);
    final totalUnits = rows.fold<double>(0, (a, r) => a + r.units);

    // geometria A4
    const pageW = 595.0, pageH = 842.0, margin = 28.0, titleH = 44.0;
    const gap = 18.0;
    const charWF = 0.62, lineHF = 1.45, base = 10.5;
    final usableW = pageW - 2 * margin;
    final usableH = pageH - 2 * margin - titleH;
    final colW = (usableW - gap) / 2;

    final fitsOneCol =
        totalUnits * lineHF * base <= usableH && maxLen * charWF * base <= usableW;

    int cols;
    double font;
    if (fitsOneCol) {
      cols = 1;
      font = base;
    } else {
      cols = 2;
      final wF = colW / (maxLen * charWF);
      final hF = usableH / ((totalUnits / 2) * lineHF);
      font = (base < wF ? base : wF);
      if (hF < font) font = hF;
      font = (font * 0.97).clamp(5.0, base);
    }

    pw.TextStyle styleFor(int kind, double f) {
      switch (kind) {
        case 0:
          return pw.TextStyle(font: bold, fontSize: f * 0.85, color: chordColor);
        case 1:
          return pw.TextStyle(font: bold, fontSize: f, color: chordColor);
        default:
          return pw.TextStyle(font: reg, fontSize: f);
      }
    }

    pw.Widget rowWidget(_Row r, double f) =>
        pw.Text(r.text, style: styleFor(r.kind, f), maxLines: 1, softWrap: false);

    pw.Widget column(List<_Row> rs, double f) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: rs.map((r) => rowWidget(r, f)).toList(),
        );

    final header = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(song.title, style: pw.TextStyle(font: bold, fontSize: 16)),
        pw.Text(
          [
            if (song.artist.isNotEmpty) song.artist,
            'Tom: ${song.key}',
            if (song.capo > 0) 'Capo ${song.capo}',
          ].join('   •   '),
          style: pw.TextStyle(font: reg, fontSize: 9, color: PdfColors.grey700),
        ),
        pw.Divider(),
      ],
    );

    pw.Widget body;
    if (cols == 1) {
      body = column(rows, font);
    } else {
      // divide as linhas em 2 colunas balanceando altura (quebra em linha em branco)
      final half = totalUnits / 2;
      double acc = 0;
      var split = rows.length;
      for (var i = 0; i < rows.length; i++) {
        acc += rows[i].units;
        if (acc >= half) {
          split = i + 1;
          // prefere quebrar logo após uma linha em branco próxima
          for (var j = i; j < rows.length && j < i + 3; j++) {
            if (rows[j].kind == 3) {
              split = j + 1;
              break;
            }
          }
          break;
        }
      }
      final left = rows.sublist(0, split);
      final right = rows.sublist(split);
      body = pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: colW, child: column(left, font)),
          pw.SizedBox(width: gap),
          pw.SizedBox(width: colW, child: column(right, font)),
        ],
      );
    }

    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(margin),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [header, pw.SizedBox(height: 4), body],
      ),
    ));

    await Printing.layoutPdf(onLayout: (_) => doc.save(), name: '$namePrefix${song.title}.pdf');
  }

  /// PDF do repertório inteiro: capa (lista numerada) + cada cifra em páginas próprias.
  static Future<void> printSetlist(String name, List<Song> songs, {int? colorArgb}) async {
    final reg = pw.Font.ttf(await rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/JetBrainsMono-Bold.ttf'));
    final chord = PdfColor.fromInt(colorArgb ?? 0xFF1A3FB8);
    final doc = pw.Document();

    pw.TextStyle st(int kind) {
      if (kind == 0) {
        return pw.TextStyle(font: bold, fontSize: 9, color: chord);
      } else if (kind == 1) {
        return pw.TextStyle(font: bold, fontSize: 10.5, color: chord);
      }
      return pw.TextStyle(font: reg, fontSize: 10.5);
    }

    // capa
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(name, style: pw.TextStyle(font: bold, fontSize: 26, color: chord)),
          pw.Divider(),
          pw.SizedBox(height: 8),
          ...List.generate(
            songs.length,
            (i) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              child: pw.Text('${i + 1}.  ${songs[i].title}',
                  style: pw.TextStyle(font: reg, fontSize: 14)),
            ),
          ),
        ],
      ),
    ));

    // uma música por página (flui p/ próxima se for longa)
    for (var i = 0; i < songs.length; i++) {
      final song = songs[i];
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('${i + 1}. ${song.title}', style: pw.TextStyle(font: bold, fontSize: 15)),
            pw.Text(
              [
                if (song.artist.isNotEmpty) song.artist,
                'Tom: ${song.key}',
                if (song.capo > 0) 'Capo ${song.capo}',
              ].join('   •   '),
              style: pw.TextStyle(font: reg, fontSize: 9, color: PdfColors.grey700),
            ),
            pw.Divider(),
          ]),
        ),
        build: (_) => _rows(song)
            .map((r) => pw.Text(r.text, style: st(r.kind), maxLines: 1, softWrap: false))
            .toList(),
      ));
    }

    await Printing.layoutPdf(onLayout: (_) => doc.save(), name: '$name.pdf');
  }
}
