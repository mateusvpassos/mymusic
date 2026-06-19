import 'package:flutter/material.dart';
import '../../models/song.dart';

/// Renderiza a cifra (acorde sobre a letra) usando fonte monoespaçada
/// para alinhamento exato: cada acorde fica na coluna do caractere `idx`.
class ChordChart extends StatelessWidget {
  final Song song; // já transposta
  final double fontSize;
  final Color chordColor;
  final void Function(String sym)? onTapChord;

  const ChordChart({
    super.key,
    required this.song,
    this.fontSize = 18,
    required this.chordColor,
    this.onTapChord,
  });

  static bool _isRefrao(String name) {
    final n = name.toLowerCase();
    return n.contains('refr') || n.contains('chorus') || n.contains('coro');
  }

  @override
  Widget build(BuildContext context) {
    final lyricStyle = TextStyle(
      fontFamily: 'ChordMono',
      fontSize: fontSize,
      height: 1.25,
      color: Theme.of(context).colorScheme.onSurface,
    );
    final chordStyle = TextStyle(
      fontFamily: 'ChordMono',
      fontSize: fontSize * 0.92,
      height: 1.0,
      fontWeight: FontWeight.w700,
      color: chordColor,
    );
    final charW = _measure('M', lyricStyle).width;
    final chordH = _measure('M', chordStyle).height;

    final blocks = <Widget>[];
    for (final sec in song.sections) {
      if (sec.name.isNotEmpty) {
        final refrao = _isRefrao(sec.name);
        blocks.add(Container(
          margin: const EdgeInsets.only(top: 18, bottom: 4),
          padding: refrao
              ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
              : EdgeInsets.zero,
          decoration: refrao
              ? BoxDecoration(
                  color: chordColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                )
              : null,
          child: Text(
            sec.name.toUpperCase(),
            style: TextStyle(
              fontSize: fontSize * 0.7,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: chordColor.withValues(alpha: 0.95),
            ),
          ),
        ));
      }
      for (final line in sec.lines) {
        blocks.add(_line(line, lyricStyle, chordStyle, charW, chordH));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocks);
  }

  Widget _chordWidget(String sym, TextStyle chord) {
    final t = Text(sym, style: chord, maxLines: 1, softWrap: false,
        textScaler: TextScaler.noScaling);
    if (onTapChord == null) return t;
    return GestureDetector(onTap: () => onTapChord!(sym), child: t);
  }

  Widget _line(SongLine line, TextStyle lyric, TextStyle chord, double charW, double chordH) {
    final hasChords = line.chords.isNotEmpty;
    final placed = _placeChords(line, chord, charW);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasChords)
          SizedBox(
            height: chordH + 2,
            child: Stack(
              children: [
                for (final p in placed)
                  Positioned(
                    left: p.x,
                    child: _chordWidget(p.sym, chord),
                  ),
              ],
            ),
          ),
        Text(line.lyric.isEmpty ? ' ' : line.lyric,
            style: lyric, maxLines: 1, softWrap: false,
            overflow: TextOverflow.clip, textScaler: TextScaler.noScaling),
      ],
    );
    return ClipRect(child: content);
  }

  // Calcula x de cada acorde a partir da coluna do char, empurrando p/ a
  // direita quando o anterior (mais largo) invadiria o espaço — evita overlap.
  List<_Placed> _placeChords(SongLine line, TextStyle chord, double charW) {
    final sorted = [...line.chords]..sort((a, b) => a.idx.compareTo(b.idx));
    const gap = 8.0;
    final out = <_Placed>[];
    double prevRight = -1e9;
    for (final c in sorted) {
      final w = _measure('${c.sym} ', chord).width;
      var x = c.idx.clamp(0, line.lyric.length) * charW;
      if (x < prevRight + gap) x = prevRight + gap;
      out.add(_Placed(c.sym, x));
      prevRight = x + w;
    }
    return out;
  }

  Size _measure(String t, TextStyle s) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: s),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.size;
  }
}

class _Placed {
  final String sym;
  final double x;
  _Placed(this.sym, this.x);
}
