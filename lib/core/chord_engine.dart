// chord_engine.dart — núcleo portável (sem widgets). Parser ChordPro, transpose.
import 'dart:math';
import '../models/song.dart';

class ChordEngine {
  static const sharp = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  static const flat = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'];
  static const _flatKeys = {'F', 'Bb', 'Eb', 'Ab', 'Db', 'Gb', 'Dm', 'Gm', 'Cm', 'Fm', 'Bbm', 'Ebm'};

  static int _noteId(String n) {
    final i = sharp.indexOf(n);
    return i >= 0 ? i : flat.indexOf(n);
  }

  static String transposeNote(String note, int steps, bool useFlat) {
    final i = _noteId(note);
    if (i < 0) return note;
    final j = ((i + steps) % 12 + 12) % 12;
    return (useFlat ? flat : sharp)[j];
  }

  static final _parts = RegExp(r'^([A-G][#b]?)([^/]*)(?:/([A-G][#b]?))?$');

  static String transposeChord(String sym, int steps, bool useFlat) {
    final m = _parts.firstMatch(sym);
    if (m == null) return sym;
    final root = transposeNote(m.group(1)!, steps, useFlat);
    final qual = m.group(2) ?? '';
    final bass = m.group(3) != null ? '/${transposeNote(m.group(3)!, steps, useFlat)}' : '';
    return '$root$qual$bass';
  }

  // "[C]Olá [G]mundo" -> SongLine(lyric:'Olá mundo', chords:[C@0, G@4])
  static SongLine parseLine(String raw) {
    final chords = <Chord>[];
    final buf = StringBuffer();
    var i = 0;
    while (i < raw.length) {
      if (raw[i] == '[') {
        final end = raw.indexOf(']', i);
        if (end > i) {
          chords.add(Chord(raw.substring(i + 1, end), buf.length));
          i = end + 1;
          continue;
        }
      }
      buf.write(raw[i]);
      i++;
    }
    return SongLine(buf.toString(), chords);
  }

  static String serializeLine(SongLine line) {
    final sorted = [...line.chords]..sort((a, b) => a.idx.compareTo(b.idx));
    final out = StringBuffer();
    var pos = 0;
    for (final c in sorted) {
      final at = c.idx.clamp(0, line.lyric.length);
      out.write(line.lyric.substring(pos, at));
      out.write('[${c.sym}]');
      pos = at;
    }
    out.write(line.lyric.substring(pos));
    return out.toString();
  }

  // Texto inteiro -> seções. Header de seção = linha começando com "#".
  static List<Section> parseSections(String text) {
    final sections = <Section>[];
    Section cur = Section('', []);
    var started = false;
    for (final raw in text.replaceAll('\r', '').split('\n')) {
      if (raw.startsWith('#')) {
        if (started) sections.add(cur);
        cur = Section(raw.substring(1).trim(), []);
        started = true;
      } else {
        cur.lines.add(parseLine(raw));
        started = true;
      }
    }
    sections.add(cur);
    return sections;
  }

  static String serializeSections(List<Section> sections) {
    return sections.map((s) {
      final head = s.name.isNotEmpty ? '#${s.name}\n' : '';
      return head + s.lines.map(serializeLine).join('\n');
    }).join('\n\n');
  }

  // ---- Importador flexível: aceita ChordPro [C]letra OU cifra
  // "acorde acima da letra" (formato Cifra Club). Detecta seção [Intro]/#.
  // aceita sufixos em qualquer ordem: G7M, D9, D4, G7+, B7(4/9), A/C#, Cmaj7...
  static final _chordTok = RegExp(
      r'^[A-G][#b]?(?:maj|min|m|M|dim|aug|sus|add|º|°|[0-9]+|[+\-]|[#b][0-9]+|\([^)]*\)|/[A-G][#b]?)*$');

  static bool _isChord(String t) => t.isNotEmpty && _chordTok.hasMatch(t);

  // remove parêntese DESBALANCEADO: "(D9"->"D9", "D4)"->"D4"; mantém "B7(4/9)", "A7(13)".
  static String _fixParens(String t) {
    if (t.startsWith('(') && !t.contains(')')) t = t.substring(1);
    if (t.endsWith(')') && !t.substring(0, t.length - 1).contains('(')) {
      t = t.substring(0, t.length - 1);
    }
    return t;
  }

  static bool _isChordLine(String line) {
    final toks = RegExp(r'\S+').allMatches(line).map((m) => m.group(0)!).toList();
    if (toks.isEmpty) return false;
    return toks.every((t) => _isChord(_fixParens(t)));
  }

  static SongLine _mergeChordLyric(String chordLine, String lyric) {
    final chords = <Chord>[];
    int maxCol = 0;
    for (final m in RegExp(r'\S+').allMatches(chordLine)) {
      chords.add(Chord(_fixParens(m.group(0)!), m.start));
      if (m.start > maxCol) maxCol = m.start;
    }
    var lyr = lyric;
    if (lyr.length < maxCol) lyr = lyr.padRight(maxCol);
    return SongLine(lyr, chords);
  }

  static final _inlineChord = RegExp(r'\[[A-G][#b]?[^\]]*\]');
  static final _sectionHead = RegExp(r'^\s*\[([^\]]+)\]\s*(.*)$');

  static List<Section> importText(String text) {
    final raw = text.replaceAll('\r', '').split('\n');
    final sections = <Section>[];
    var cur = Section('', []);
    var started = false;
    void newSection(String name) {
      if (started) sections.add(cur);
      cur = Section(name, []);
      started = true;
    }

    for (var i = 0; i < raw.length; i++) {
      var line = raw[i];

      if (line.startsWith('#')) {
        newSection(line.substring(1).trim());
        continue;
      }
      final sm = _sectionHead.firstMatch(line);
      if (sm != null && !_isChord(sm.group(1)!.trim())) {
        newSection(sm.group(1)!.trim());
        final rest = sm.group(2)!;
        if (rest.trim().isEmpty) continue;
        line = rest;
      }

      if (_inlineChord.hasMatch(line)) {
        cur.lines.add(parseLine(line));
        started = true;
        continue;
      }

      if (_isChordLine(line)) {
        final next = i + 1 < raw.length ? raw[i + 1] : null;
        final nextIsLyric = next != null &&
            next.trim().isNotEmpty &&
            !next.startsWith('#') &&
            !_isChordLine(next) &&
            _sectionHead.firstMatch(next) == null;
        if (nextIsLyric) {
          cur.lines.add(_mergeChordLyric(line, next));
          i++;
        } else {
          cur.lines.add(_mergeChordLyric(line, ''));
        }
        started = true;
        continue;
      }

      cur.lines.add(SongLine(line, []));
      started = true;
    }
    if (started) sections.add(cur);
    return sections;
  }

  // primeiro acorde encontrado (p/ sugerir tom)
  static String? firstChord(List<Section> sections) {
    for (final s in sections) {
      for (final l in s.lines) {
        if (l.chords.isNotEmpty) {
          final sorted = [...l.chords]..sort((a, b) => a.idx.compareTo(b.idx));
          return sorted.first.sym;
        }
      }
    }
    return null;
  }

  static String rootOf(String chord) {
    final m = _parts.firstMatch(chord);
    return m != null ? m.group(1)! : chord;
  }

  // sugere tom pelo 1º acorde, mantendo "m" se for menor (ex.: Bm)
  static String? suggestKey(List<Section> sections) {
    final fc = firstChord(sections);
    if (fc == null) return null;
    final m = _parts.firstMatch(fc);
    if (m == null) return rootOf(fc);
    final root = m.group(1)!;
    final qual = m.group(2) ?? '';
    final minor = qual.startsWith('m') && !qual.startsWith('maj');
    return minor ? '${root}m' : root;
  }

  static bool _preferFlat(String key, int steps) {
    return _flatKeys.contains(transposeChord(key.isEmpty ? 'C' : key, steps, true));
  }

  static Song transposeSong(Song song, int steps) {
    final useFlat = _preferFlat(song.key, steps);
    final out = song.copy();
    out.key = transposeChord(song.key.isEmpty ? 'C' : song.key, steps, useFlat);
    for (final sec in out.sections) {
      for (final ln in sec.lines) {
        for (final c in ln.chords) {
          c.sym = transposeChord(c.sym, steps, useFlat);
        }
      }
    }
    return out;
  }

  // distância em semitons (-6..+5) de 'from' p/ 'to'
  static int stepsBetween(String from, String to) {
    final a = _noteId(from), b = _noteId(to);
    if (a < 0 || b < 0) return 0;
    var d = (b - a) % 12;
    if (d > 6) d -= 12;
    if (d < -6) d += 12;
    return d;
  }

  static final _rng = Random();
  static String uid() =>
      DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
      _rng.nextInt(1 << 30).toRadixString(36);
}
