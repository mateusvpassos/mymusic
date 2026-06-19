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

/// Exporta a cifra como PNG do tamanho exato do conteúdo (fundo branco).
class ImageExport {
  static TextPainter _tp(String t, TextStyle s) => TextPainter(
        text: TextSpan(text: t, style: s),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout();

  static Future<void> shareImage(Song song,
      {required Color chordColor, double fontSize = 22, double scale = 3}) async {
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

    const padX = 32.0, padY = 28.0;
    double y = padY, maxRight = 0;
    final ops = <_Op>[];
    void add(String t, TextStyle s, double x) {
      final p = _tp(t.isEmpty ? ' ' : t, s);
      ops.add(_Op(x, y, p));
      maxRight = max(maxRight, x + p.width);
    }

    // título + subtítulo
    add(song.title, titleStyle, padX);
    y += titleStyle.fontSize! * 1.3;
    final sub = [
      if (song.artist.isNotEmpty) song.artist,
      'Tom: ${song.key}',
      if (song.capo > 0) 'Capo ${song.capo}',
    ].join('   •   ');
    add(sub, subStyle, padX);
    y += subStyle.fontSize! * 1.6;

    for (final sec in song.sections) {
      if (sec.name.isNotEmpty) {
        y += fontSize * 0.5;
        add(sec.name.toUpperCase(), headerStyle, padX);
        y += headerStyle.fontSize! * 1.5;
      }
      for (final line in sec.lines) {
        if (line.chords.isNotEmpty) {
          final sorted = [...line.chords]..sort((a, b) => a.idx.compareTo(b.idx));
          double prevRight = -1e9;
          for (final c in sorted) {
            final p = _tp(c.sym, chordStyle);
            var x = padX + c.idx.clamp(0, line.lyric.length) * charW;
            if (x < prevRight + 8) x = prevRight + 8;
            ops.add(_Op(x, y, p));
            maxRight = max(maxRight, x + p.width);
            prevRight = x + p.width + charW * 0.3;
          }
          y += chordH + 2;
        }
        add(line.lyric, lyricStyle, padX);
        y += lyricH;
      }
    }
    final w = maxRight + padX;
    final h = y + padY;

    // desenha
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFFFFFFFF));
    for (final op in ops) {
      op.p.paint(canvas, Offset(op.x, op.y));
    }
    final img = await recorder.endRecording().toImage((w * scale).ceil(), (h * scale).ceil());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;

    final dir = await getTemporaryDirectory();
    final safe = song.title.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
    final file = File('${dir.path}/$safe.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    await Share.shareXFiles([XFile(file.path)], subject: song.title);
  }
}
