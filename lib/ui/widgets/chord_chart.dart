import 'package:flutter/material.dart';
import '../../models/song.dart';

/// Renderiza a cifra (acorde sobre a letra) usando fonte monoespaçada
/// para alinhamento exato: cada acorde fica na coluna do caractere `idx`.
class ChordChart extends StatelessWidget {
  final Song song; // já transposta
  final double fontSize;
  final Color chordColor;
  final void Function(String sym)? onTapChord;
  // só a letra, em fonte comum e quebrando por palavra (p/ quem canta)
  final bool lyricsOnly;

  const ChordChart({
    super.key,
    required this.song,
    this.fontSize = 18,
    required this.chordColor,
    this.onTapChord,
    this.lyricsOnly = false,
  });

  static bool _isRefrao(String name) {
    final n = name.toLowerCase();
    return n.contains('refr') || n.contains('chorus') || n.contains('coro');
  }

  /// Quebra uma linha de cifra em pedaços de até [max] colunas.
  ///
  /// Corta em espaço da letra e nunca no meio de um acorde: cada acorde vai
  /// junto com a sílaba dele. A continuação vem recuada 2 colunas, como em
  /// songbook. Sem isso, verso mais largo que a tela era cortado — sumia o
  /// fim da letra e os últimos acordes.
  static List<SongLine> wrapLine(SongLine l, int max) {
    const indent = 2;
    if (max < 8) return [l];
    int ends(SongLine x) {
      var e = x.lyric.trimRight().length;
      for (final c in x.chords) {
        if (c.idx + c.sym.length > e) e = c.idx + c.sym.length;
      }
      return e;
    }

    if (ends(l) <= max) return [l];

    // corte = coluna onde a próxima parte começa. Precisa ser espaço na letra
    // e nenhum acorde da primeira parte pode passar de [max].
    bool cabe(int cut) {
      for (final c in l.chords) {
        if (c.idx < cut && c.idx + c.sym.length > max) return false;
      }
      return true;
    }

    var cut = -1;
    final lyr = l.lyric.padRight(max + 1);
    for (var i = max; i > max ~/ 3; i--) {
      if (lyr[i] == ' ' && cabe(i)) {
        cut = i;
        break;
      }
    }
    if (cut < 0) {
      // palavra/acorde sem espaço nenhum: corte seco antes do 1º acorde que
      // não cabe (ou em max)
      cut = max;
      for (final c in l.chords) {
        if (c.idx < cut && c.idx + c.sym.length > max && c.idx > 0) cut = c.idx;
      }
    }

    // pula os espaços do começo da continuação
    var start = cut;
    while (start < l.lyric.length && l.lyric[start] == ' ') {
      start++;
    }
    // acorde parado em espaço entre o corte e o início vai p/ a continuação
    final firstChords = l.chords.where((c) => c.idx < cut).toList();
    final restChords = l.chords
        .where((c) => c.idx >= cut)
        .map(
          (c) => Chord(c.sym, indent + (c.idx - start < 0 ? 0 : c.idx - start)),
        )
        .toList();
    final first = SongLine(
      l.lyric.substring(0, cut.clamp(0, l.lyric.length)).trimRight(),
      firstChords,
    );
    final restLyric = start < l.lyric.length ? l.lyric.substring(start) : '';
    final rest = SongLine(' ' * indent + restLyric, restChords);
    if (restLyric.trim().isEmpty && restChords.isEmpty) return [first];
    // evita laço: se não andou nada, devolve como está
    if (start <= 0) return [l];
    return [first, ...wrapLine(rest, max)];
  }

  /// Seções como ficam no modo só letra: sem as linhas que só têm acorde
  /// (intro, solo) e sem as seções que ficaram vazias por isso.
  static List<Section> letra(Song song) {
    final out = <Section>[];
    for (final sec in song.sections) {
      final linhas = <SongLine>[];
      for (final l in sec.lines) {
        final t = l.lyric.trim();
        if (t.isEmpty && l.chords.isNotEmpty) continue;
        if (t.isEmpty && (linhas.isEmpty || linhas.last.lyric.isEmpty))
          continue;
        linhas.add(SongLine(t, const []));
      }
      while (linhas.isNotEmpty && linhas.last.lyric.isEmpty) {
        linhas.removeLast();
      }
      if (linhas.isNotEmpty) out.add(Section(sec.name, linhas));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (lyricsOnly) return _buildLetra(context);
    return LayoutBuilder(
      builder: (context, box) => _build(context, box.maxWidth),
    );
  }

  Widget _build(BuildContext context, double maxWidth) {
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
    final maxCols = maxWidth.isFinite && charW > 0
        ? (maxWidth / charW).floor()
        : 1 << 20;

    final blocks = <Widget>[];
    for (final sec in song.sections) {
      if (sec.name.isNotEmpty) {
        final refrao = _isRefrao(sec.name);
        blocks.add(
          Container(
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
          ),
        );
      }
      // linhas em branco no fim da seção são sobra (a seção seguinte já tem
      // espaço próprio): não desenha — vale p/ música que veio de versão
      // antiga por sync
      var fim = sec.lines.length;
      while (fim > 0 &&
          sec.lines[fim - 1].chords.isEmpty &&
          sec.lines[fim - 1].lyric.trim().isEmpty) {
        fim--;
      }
      for (final line in sec.lines.take(fim)) {
        for (final part in wrapLine(line, maxCols)) {
          blocks.add(_line(part, lyricStyle, chordStyle, charW, chordH));
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  Widget _buildLetra(BuildContext context) {
    final cor = Theme.of(context).colorScheme.onSurface;
    final blocks = <Widget>[];
    for (final sec in letra(song)) {
      final refrao = _isRefrao(sec.name);
      if (sec.name.isNotEmpty) {
        blocks.add(
          Padding(
            padding: EdgeInsets.only(top: fontSize * 0.9, bottom: 2),
            child: Text(
              sec.name.toUpperCase(),
              style: TextStyle(
                fontSize: fontSize * 0.55,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: chordColor,
              ),
            ),
          ),
        );
      } else if (blocks.isNotEmpty) {
        blocks.add(SizedBox(height: fontSize * 0.6));
      }
      for (final l in sec.lines) {
        blocks.add(
          Text(
            l.lyric.isEmpty ? ' ' : l.lyric,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.3,
              color: cor,
              // refrão em negrito, como no PDF: todo mundo canta junto
              fontWeight: refrao ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  Widget _chordWidget(String sym, TextStyle chord) {
    final t = Text(
      sym,
      style: chord,
      maxLines: 1,
      softWrap: false,
      textScaler: TextScaler.noScaling,
    );
    if (onTapChord == null) return t;
    return GestureDetector(onTap: () => onTapChord!(sym), child: t);
  }

  Widget _line(
    SongLine line,
    TextStyle lyric,
    TextStyle chord,
    double charW,
    double chordH,
  ) {
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
                  Positioned(left: p.x, child: _chordWidget(p.sym, chord)),
              ],
            ),
          ),
        Text(
          line.lyric.isEmpty ? ' ' : line.lyric,
          style: lyric,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          textScaler: TextScaler.noScaling,
        ),
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
