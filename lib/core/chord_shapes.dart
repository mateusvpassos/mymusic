import 'package:flutter/material.dart';

/// Forma de acorde no braço: 6 cordas (mizE..agudaE), -1=abafada, 0=solta.
class ChordShape {
  final int baseFret; // 0 = casas abertas
  final List<int> frets; // valores absolutos por corda
  ChordShape(this.baseFret, this.frets);
}

class ChordShapes {
  static const _pc = {
    'C': 0, 'C#': 1, 'Db': 1, 'D': 2, 'D#': 3, 'Eb': 3, 'E': 4,
    'F': 5, 'F#': 6, 'Gb': 6, 'G': 7, 'G#': 8, 'Ab': 8, 'A': 9,
    'A#': 10, 'Bb': 10, 'B': 11,
  };

  // templates relativos ao barre (0 = corda no barre/solta na posição)
  static const _eShape = {
    'maj': [0, 2, 2, 1, 0, 0],
    'm': [0, 2, 2, 0, 0, 0],
    '7': [0, 2, 0, 1, 0, 0],
    'm7': [0, 2, 0, 0, 0, 0],
    'maj7': [0, 2, 1, 1, 0, 0],
    'sus4': [0, 2, 2, 2, 0, 0],
  };
  static const _aShape = {
    'maj': [-1, 0, 2, 2, 2, 0],
    'm': [-1, 0, 2, 2, 1, 0],
    '7': [-1, 0, 2, 0, 2, 0],
    'm7': [-1, 0, 2, 0, 1, 0],
    'maj7': [-1, 0, 2, 1, 2, 0],
    'sus4': [-1, 0, 2, 2, 3, 0],
  };

  static String _quality(String q) {
    if (q.contains('maj7') || q.contains('M7')) return 'maj7';
    if (q.startsWith('m') && !q.startsWith('maj')) {
      return q.contains('7') ? 'm7' : 'm';
    }
    if (q.contains('7')) return '7';
    if (q.contains('sus')) return 'sus4';
    return 'maj';
  }

  /// Gera uma forma tocável (E-shape ou A-shape, a de casa mais baixa).
  static ChordShape? forChord(String sym) {
    final m = RegExp(r'^([A-G][#b]?)([^/]*)').firstMatch(sym);
    if (m == null) return null;
    final rootPc = _pc[m.group(1)!];
    if (rootPc == null) return null;
    final qual = _quality(m.group(2) ?? '');

    final baseE = ((rootPc - 4) % 12 + 12) % 12; // raiz na 6ª corda (E)
    final baseA = ((rootPc - 9) % 12 + 12) % 12; // raiz na 5ª corda (A)

    final useA = baseA < baseE;
    final base = useA ? baseA : baseE;
    final tmpl = (useA ? _aShape : _eShape)[qual]!;

    final frets = tmpl
        .map((t) => t < 0 ? -1 : (base == 0 ? t : base + t))
        .toList();
    return ChordShape(base, frets);
  }
}

/// Desenho do braço (diagrama de acorde).
class ChordDiagram extends StatelessWidget {
  final ChordShape shape;
  final Color color;
  final double size;
  const ChordDiagram({super.key, required this.shape, required this.color, this.size = 160});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 1.15,
      child: CustomPaint(painter: _DiagramPainter(shape, color)),
    );
  }
}

class _DiagramPainter extends CustomPainter {
  final ChordShape s;
  final Color color;
  _DiagramPainter(this.s, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const frets = 5;
    const strings = 6;
    final left = size.width * 0.12;
    final top = size.height * 0.12;
    final w = size.width * 0.76;
    final h = size.height * 0.7;
    final dx = w / (strings - 1);
    final dy = h / frets;

    final line = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1.4;
    final dot = Paint()..color = color;
    final txt = (String t, Offset o, double fs, {Color? c}) {
      final tp = TextPainter(
        text: TextSpan(
            text: t,
            style: TextStyle(color: c ?? color, fontSize: fs, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, o - Offset(tp.width / 2, tp.height / 2));
    };

    // pestana (casa base) ou nut grosso
    final base = s.baseFret;
    if (base == 0) {
      canvas.drawRect(Rect.fromLTWH(left, top - 3, w, 3.5), line..color = color);
    } else {
      txt('${base}fr', Offset(left - size.width * 0.07, top + dy / 2), 12);
    }

    for (var i = 0; i <= frets; i++) {
      final y = top + dy * i;
      canvas.drawLine(Offset(left, y), Offset(left + w, y),
          line..color = color.withValues(alpha: 0.6));
    }
    for (var i = 0; i < strings; i++) {
      final x = left + dx * i;
      canvas.drawLine(Offset(x, top), Offset(x, top + h),
          line..color = color.withValues(alpha: 0.6));
    }

    for (var i = 0; i < strings; i++) {
      final x = left + dx * i;
      final f = s.frets[i];
      if (f < 0) {
        txt('×', Offset(x, top - size.height * 0.06), 13, c: color.withValues(alpha: 0.8));
      } else if (f == 0) {
        canvas.drawCircle(Offset(x, top - size.height * 0.055), 4,
            Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = color);
      } else {
        final rel = base == 0 ? f : f - base + 1;
        final y = top + dy * (rel - 0.5);
        canvas.drawCircle(Offset(x, y), dx * 0.32, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DiagramPainter old) =>
      old.s != s || old.color != color;
}
