import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/song.dart';

class _Op {
  final double x, y;
  final TextPainter p;
  _Op(this.x, this.y, this.p);
}

/// Bloco de layout (linha de cifra ou cabeçalho de seção) com coords locais.
class _Block {
  final List<_Op> ops;
  final double h, w;
  final bool keepWithNext; // cabeçalho não pode ficar sozinho no fim da coluna
  _Block(this.ops, this.h, this.w, {this.keepWithNext = false});
}

/// Exporta a cifra como PNG do tamanho exato do conteúdo (fundo branco).
class ImageExport {
  static TextPainter _tp(String t, TextStyle s) => TextPainter(
        text: TextSpan(text: t, style: s),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout();

  static String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[^\w\s.-]'), '').trim();

  static Future<void> _save(ui.Image img, String name, String subject) async {
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_sanitize(name)}.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    await Share.shareXFiles([XFile(file.path)], subject: subject);
  }

  static Future<void> shareImage(Song song,
      {required Color chordColor,
      double fontSize = 22,
      double scale = 3,
      String namePrefix = ''}) async {
    const black = Color(0xFF111111);
    final lyricStyle = TextStyle(
        fontFamily: 'ChordMono', fontSize: fontSize, height: 1.25, color: black);
    final chordStyle = TextStyle(
        fontFamily: 'ChordMono',
        fontSize: fontSize * 0.92,
        height: 1.0,
        fontWeight: FontWeight.w700,
        color: chordColor);
    final headerStyle = TextStyle(
        fontFamily: 'ChordMono',
        fontSize: fontSize * 0.72,
        fontWeight: FontWeight.w800,
        color: chordColor);
    final titleStyle = TextStyle(
        fontFamily: 'ChordMono',
        fontSize: fontSize * 1.25,
        fontWeight: FontWeight.w800,
        color: black);
    final subStyle = TextStyle(
        fontFamily: 'ChordMono', fontSize: fontSize * 0.6, color: const Color(0xFF666666));

    final charW = _tp('M', lyricStyle).width;
    final chordH = _tp('M', chordStyle).height;
    final lyricH = _tp('M', lyricStyle).height;

    const padX = 32.0, padY = 28.0, colGap = 44.0;

    // monta blocos (coords locais, x relativo ao início da coluna)
    final blocks = <_Block>[];
    for (final sec in song.sections) {
      if (sec.name.isNotEmpty) {
        final p = _tp(sec.name.toUpperCase(), headerStyle);
        blocks.add(_Block(
          [_Op(0, fontSize * 0.5, p)],
          fontSize * 0.5 + headerStyle.fontSize! * 1.5,
          p.width,
          keepWithNext: true,
        ));
      }
      for (final line in sec.lines) {
        final ops = <_Op>[];
        double h = 0, w = 0;
        if (line.chords.isNotEmpty) {
          final sorted = [...line.chords]..sort((a, b) => a.idx.compareTo(b.idx));
          double prevRight = -1e9;
          for (final c in sorted) {
            final p = _tp(c.sym, chordStyle);
            var x = c.idx.clamp(0, line.lyric.length) * charW;
            if (x < prevRight + 8) x = prevRight + 8;
            ops.add(_Op(x, 0, p));
            w = max(w, x + p.width);
            prevRight = x + p.width + charW * 0.3;
          }
          h = chordH + 2;
        }
        final p = _tp(line.lyric.isEmpty ? ' ' : line.lyric, lyricStyle);
        ops.add(_Op(0, h, p));
        w = max(w, p.width);
        h += lyricH;
        blocks.add(_Block(ops, h, w));
      }
    }

    final contentH = blocks.fold(0.0, (a, b) => a + b.h);
    final colW = blocks.fold(0.0, (a, b) => max(a, b.w));
    // muito extenso p/ largura -> 2 colunas (imagem menos "espichada")
    final cols = contentH > colW * 1.8 && blocks.length > 6 ? 2 : 1;

    // distribui blocos: coluna 1 até ~metade da altura, sem cortar após header
    final colBlocks = List.generate(cols, (_) => <_Block>[]);
    if (cols == 1) {
      colBlocks[0].addAll(blocks);
    } else {
      final target = contentH / 2;
      double acc = 0;
      int split = blocks.length;
      for (var i = 0; i < blocks.length; i++) {
        acc += blocks[i].h;
        if (acc >= target) {
          split = i + 1;
          break;
        }
      }
      // não deixa header órfão no fim da 1ª coluna
      while (split > 1 && blocks[split - 1].keepWithNext) {
        split--;
      }
      colBlocks[0].addAll(blocks.take(split));
      colBlocks[1].addAll(blocks.skip(split));
    }

    // título + subtítulo (largura total)
    final headOps = <_Op>[];
    double y = padY;
    double headRight = 0;
    final titleP = _tp(song.title, titleStyle);
    headOps.add(_Op(padX, y, titleP));
    headRight = max(headRight, padX + titleP.width);
    y += titleStyle.fontSize! * 1.3;
    final sub = [
      if (song.artist.isNotEmpty) song.artist,
      'Tom: ${song.key}',
      if (song.capo > 0) 'Capo ${song.capo}',
    ].join('   •   ');
    final subP = _tp(sub, subStyle);
    headOps.add(_Op(padX, y, subP));
    headRight = max(headRight, padX + subP.width);
    y += subStyle.fontSize! * 1.6;
    final colTop = y;

    // posiciona colunas
    final ops = <_Op>[...headOps];
    double maxBottom = colTop;
    final colWidths = List.generate(
        cols, (i) => colBlocks[i].fold(0.0, (a, b) => max(a, b.w)));
    double colX = padX;
    for (var i = 0; i < cols; i++) {
      double cy = colTop;
      for (final b in colBlocks[i]) {
        for (final op in b.ops) {
          ops.add(_Op(colX + op.x, cy + op.y, op.p));
        }
        cy += b.h;
      }
      maxBottom = max(maxBottom, cy);
      colX += colWidths[i] + colGap;
    }
    final w = max(headRight, colX - colGap) + padX;
    final h = maxBottom + padY;

    // desenha
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFFFFFFFF));
    if (cols == 2) {
      final dx = padX + colWidths[0] + colGap / 2;
      canvas.drawLine(
          Offset(dx, colTop),
          Offset(dx, maxBottom),
          Paint()
            ..color = const Color(0xFFDDDDDD)
            ..strokeWidth = 1.5);
    }
    for (final op in ops) {
      op.p.paint(canvas, Offset(op.x, op.y));
    }
    final img = await recorder.endRecording().toImage((w * scale).ceil(), (h * scale).ceil());
    await _save(img, '$namePrefix${song.title}', song.title);
  }

  /// Imagem da lista de músicas do repertório (título + lista numerada).
  static Future<void> shareSetlist(String name, List<String> titles,
      {required Color chordColor, double fontSize = 26, double scale = 3}) async {
    const black = Color(0xFF111111);
    final titleStyle = TextStyle(
        fontFamily: 'ChordMono',
        fontSize: fontSize * 1.3,
        fontWeight: FontWeight.w800,
        color: chordColor);
    final itemStyle = TextStyle(fontFamily: 'ChordMono', fontSize: fontSize, color: black);
    final numStyle = TextStyle(
        fontFamily: 'ChordMono', fontSize: fontSize, fontWeight: FontWeight.w800, color: chordColor);

    const padX = 36.0, padY = 32.0;
    double y = padY, maxRight = 0;
    final ops = <_Op>[];
    void place(String t, TextStyle s, double x) {
      final p = _tp(t.isEmpty ? ' ' : t, s);
      ops.add(_Op(x, y, p));
      maxRight = max(maxRight, x + p.width);
    }

    place(name, titleStyle, padX);
    y += titleStyle.fontSize! * 1.7;

    final numW = _tp('${titles.length}.  ', numStyle).width;
    for (var i = 0; i < titles.length; i++) {
      place('${i + 1}.', numStyle, padX);
      place(titles[i], itemStyle, padX + numW);
      y += itemStyle.fontSize! * 1.55;
    }

    final w = maxRight + padX;
    final h = y + padY - itemStyle.fontSize! * 0.4;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFFFFFFFF));
    for (final op in ops) {
      op.p.paint(canvas, Offset(op.x, op.y));
    }
    final img = await recorder.endRecording().toImage((w * scale).ceil(), (h * scale).ceil());
    await _save(img, name, name);
  }
}
