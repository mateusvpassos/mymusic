import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/song.dart';

class PdfExport {
  // linha de acordes alinhada por coluna (empurra se sobrepor)
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

  static Future<void> printOrShare(Song song) async {
    final reg = pw.Font.ttf(await rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/JetBrainsMono-Bold.ttf'));
    final doc = pw.Document();
    final chordColor = PdfColor.fromInt(0xFF1A3FB8);

    final body = <pw.Widget>[];
    for (final sec in song.sections) {
      if (sec.name.isNotEmpty) {
        body.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10, bottom: 2),
          child: pw.Text(sec.name.toUpperCase(),
              style: pw.TextStyle(font: bold, fontSize: 9, color: chordColor)),
        ));
      }
      for (final l in sec.lines) {
        if (l.chords.isNotEmpty) {
          body.add(pw.Text(_chordLine(l),
              style: pw.TextStyle(font: bold, fontSize: 10, color: chordColor)));
        }
        body.add(pw.Text(l.lyric.isEmpty ? ' ' : l.lyric,
            style: pw.TextStyle(font: reg, fontSize: 10)));
      }
    }

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
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
        ]),
      ),
      build: (_) => body,
    ));

    await Printing.layoutPdf(
      onLayout: (_) => doc.save(),
      name: '${song.title}.pdf',
    );
  }
}
