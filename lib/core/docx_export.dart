import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart' show Color;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/song.dart';
import 'chart_layout.dart';

/// Exporta a cifra como .docx (Word), sempre em **uma coluna só**, de cima
/// para baixo — é mais fácil de editar depois no Word.
///
/// Um .docx é um zip de XMLs. Sem a amarra de caber numa página (o Word
/// pagina sozinho), o tamanho da fonte é limitado só pela largura da linha
/// mais longa, até o tamanho alvo.
class DocxExport {
  // twips = 1/20 pt. O Word mede quase tudo nessa unidade.
  static int _tw(double pt) => (pt * 20).round();

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _hex(Color c) =>
      (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  static String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[^\w\s.-]'), '').trim();

  /// Um parágrafo de uma linha da cifra, com altura travada.
  static String _p(ChartRow r, double font, String chordHex) {
    final lineH = _tw(font * r.units * ChartLayout.lineHF);
    // linha em branco: parágrafo vazio só com a altura
    final spacing = '<w:spacing w:before="0" w:after="0" '
        'w:line="$lineH" w:lineRule="exact"/>';
    if (r.kind == 3) {
      return '<w:p><w:pPr>$spacing</w:pPr></w:p>';
    }

    final size = r.kind == 0 ? font * 0.85 : font;
    final bold = r.kind == 0 || r.kind == 1 || r.refrao;
    final colored = r.kind == 0 || r.kind == 1;
    final rPr = StringBuffer('<w:rPr>')
      ..write('<w:rFonts w:ascii="JetBrains Mono" w:hAnsi="JetBrains Mono" '
          'w:cs="Consolas"/>')
      ..write(bold ? '<w:b/>' : '')
      ..write(colored ? '<w:color w:val="$chordHex"/>' : '')
      // half-points
      ..write('<w:sz w:val="${(size * 2).round()}"/>')
      ..write('<w:szCs w:val="${(size * 2).round()}"/>')
      // mesmo aperto entre letras do PDF, p/ o acorde cair na sílaba certa
      ..write('<w:spacing w:val="${_tw(size * ChartLayout.track)}"/>')
      ..write('</w:rPr>');

    // acorde não pode ser separado da sua letra, nem o nome da seção da
    // primeira linha dela; no resto deixa o Word quebrar a página à vontade
    final keep = (r.kind == 0 || r.kind == 1) ? '<w:keepNext/>' : '';
    return '<w:p><w:pPr>$spacing$keep</w:pPr>'
        '<w:r>$rPr<w:t xml:space="preserve">${_esc(r.text)}</w:t></w:r></w:p>';
  }

  static String _col(List<ChartRow> rs, double font, String chordHex) =>
      rs.map((r) => _p(r, font, chordHex)).join();

  /// Maior fonte em que a linha mais longa ainda cabe na largura da página.
  ///
  /// Não olha altura: o documento corre em uma coluna e o Word quebra a
  /// página sozinho quando precisa.
  static double fontFor(Song song) {
    final len = ChartLayout.maxLen(ChartLayout.rows(song));
    final porLargura = ChartLayout.usableW / (len * ChartLayout.charWF);
    return porLargura < ChartLayout.base ? porLargura : ChartLayout.base;
  }

  static String _songBody(Song song, String headerText, String chordHex) {
    final font = fontFor(song);
    final sb = StringBuffer();

    // cabeçalho
    sb.write('<w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr>'
        '<w:r><w:rPr><w:rFonts w:ascii="JetBrains Mono" w:hAnsi="JetBrains Mono"/>'
        '<w:b/><w:sz w:val="28"/></w:rPr>'
        '<w:t xml:space="preserve">${_esc(headerText)}</w:t></w:r></w:p>');
    final sub = [
      if (song.artist.isNotEmpty) song.artist,
      'Tom: ${song.key}',
      if (song.capo > 0) 'Capo ${song.capo}',
    ].join('   •   ');
    sb.write('<w:p><w:pPr><w:spacing w:before="0" w:after="60"/>'
        '<w:pBdr><w:bottom w:val="single" w:sz="6" w:color="999999"/></w:pBdr>'
        '</w:pPr>'
        '<w:r><w:rPr><w:rFonts w:ascii="JetBrains Mono" w:hAnsi="JetBrains Mono"/>'
        '<w:sz w:val="18"/><w:color w:val="666666"/></w:rPr>'
        '<w:t xml:space="preserve">${_esc(sub)}</w:t></w:r></w:p>');

    sb.write(_col(ChartLayout.rows(song), font, chordHex));
    return sb.toString();
  }

  static String _document(String body) {
    const m = ChartLayout.margin;
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>$body'
        '<w:sectPr>'
        '<w:pgSz w:w="${_tw(ChartLayout.pageW)}" w:h="${_tw(ChartLayout.pageH)}"/>'
        '<w:pgMar w:top="${_tw(m)}" w:right="${_tw(m)}" w:bottom="${_tw(m)}" '
        'w:left="${_tw(m)}" w:header="0" w:footer="0" w:gutter="0"/>'
        '</w:sectPr></w:body></w:document>';
  }

  static const _contentTypes =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '</Types>';

  static const _rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
      'Target="word/document.xml"/></Relationships>';

  /// Bytes de um .docx com o `body` já montado.
  static List<int> buildDocx(String body) {
    final ar = Archive();
    void add(String path, String xml) {
      // o XML declara UTF-8: codeUnits (UTF-16) quebraria todo acento
      final b = utf8.encode(xml);
      ar.addFile(ArchiveFile(path, b.length, b));
    }

    add('[Content_Types].xml', _contentTypes);
    add('_rels/.rels', _rels);
    add('word/document.xml', _document(body));
    return ZipEncoder().encode(ar);
  }

  static String songBody(Song song, {required Color chordColor, String namePrefix = ''}) =>
      _songBody(song, '$namePrefix${song.title}', _hex(chordColor));

  static Future<void> _share(List<int> bytes, String name) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/${_sanitize(name)}.docx');
    await f.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(f.path)], subject: name);
  }

  static Future<void> shareSong(Song song,
      {required Color chordColor, String namePrefix = ''}) async {
    final body = _songBody(song, song.title, _hex(chordColor));
    await _share(buildDocx(body), '$namePrefix${song.title}');
  }

  /// Repertório: capa com a lista numerada + uma cifra por página.
  static Future<void> shareSetlist(String name, List<Song> songs,
      {required Color chordColor}) async {
    final hex = _hex(chordColor);
    final sb = StringBuffer();

    sb.write('<w:p><w:pPr><w:spacing w:after="120"/></w:pPr>'
        '<w:r><w:rPr><w:rFonts w:ascii="JetBrains Mono" w:hAnsi="JetBrains Mono"/>'
        '<w:b/><w:sz w:val="52"/><w:color w:val="$hex"/></w:rPr>'
        '<w:t xml:space="preserve">${_esc(name)}</w:t></w:r></w:p>');
    for (var i = 0; i < songs.length; i++) {
      sb.write('<w:p><w:pPr><w:spacing w:before="40" w:after="40"/></w:pPr>'
          '<w:r><w:rPr><w:rFonts w:ascii="JetBrains Mono" w:hAnsi="JetBrains Mono"/>'
          '<w:sz w:val="28"/></w:rPr>'
          '<w:t xml:space="preserve">${i + 1}.  ${_esc(songs[i].title)}</w:t>'
          '</w:r></w:p>');
    }

    for (var i = 0; i < songs.length; i++) {
      sb.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
      sb.write(_songBody(songs[i], '${i + 1}. ${songs[i].title}', hex));
    }
    await _share(buildDocx(sb.toString()), name);
  }
}
