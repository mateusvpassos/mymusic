// chord_engine.dart — núcleo portável (sem widgets). Parser ChordPro, transpose.
//
// Espelhado em mymusic-web/src/chordEngine.ts: mudança aqui vai lá também.
import 'dart:math';
import '../models/song.dart';

/// Metadados achados no texto colado (diretivas ChordPro, "Tom: G", "Capo 2").
class SongMeta {
  String? title, artist, key;
  int? capo;
}

class ChordEngine {
  static const sharp = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  static const flat = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'];
  static const _flatKeys = {'F', 'Bb', 'Eb', 'Ab', 'Db', 'Gb', 'Dm', 'Gm', 'Cm', 'Fm', 'Bbm', 'Ebm'};
  // grafias raras que não estão nas duas escalas acima
  static const _enharm = {'Cb': 11, 'Fb': 4, 'E#': 5, 'B#': 0};

  static int _noteId(String n) {
    final i = sharp.indexOf(n);
    if (i >= 0) return i;
    final j = flat.indexOf(n);
    return j >= 0 ? j : (_enharm[n] ?? -1);
  }

  static String transposeNote(String note, int steps, bool useFlat) {
    final i = _noteId(note);
    if (i < 0) return note;
    final j = ((i + steps) % 12 + 12) % 12;
    return (useFlat ? flat : sharp)[j];
  }

  // Raiz + qualidade + baixo opcional. O meio é preguiçoso e o baixo só conta
  // se for uma NOTA: "D7/9" é tensão (qualidade "7/9"), "D/F#" é baixo.
  static final _parts = RegExp(r'^([A-G][#b]?)(.*?)(?:/([A-G][#b]?))?$');

  static String transposeChord(String sym, int steps, bool useFlat) {
    if (!_isChord(sym)) return sym; // anotação: (2x), |, N.C. ...
    final m = _parts.firstMatch(sym);
    if (m == null) return sym;
    final root = transposeNote(m.group(1)!, steps, useFlat);
    final qual = m.group(2) ?? '';
    final bass = m.group(3) != null ? '/${transposeNote(m.group(3)!, steps, useFlat)}' : '';
    return '$root$qual$bass';
  }

  // ---- tokens ----

  // aceita sufixos em qualquer ordem: G7M, D9, D4, G7+, B7(4/9), A/C#, Cmaj7,
  // D7/9 (tensão com barra), Bø, Cº...
  static final _chordTok = RegExp(
      r'^[A-G][#b]?(?:maj|min|m|M|dim|aug|sus|add|º|°|ø|[0-9]+|[+\-]|[#b][0-9]+'
      r'|\([^)]*\)|/[A-G][#b]?|/[#b+\-]?[0-9]+[+\-]?)*$');

  // marcações que aparecem no meio das linhas de acorde e não podem
  // fazer a linha inteira virar letra: (2x), x2, bis, |, -, /, N.C., %
  static final _annotTok = RegExp(
      r'^(?:\(?\s*(?:\d+\s*[xX]|[xX]\s*\d+|bis|Bis|BIS)\s*\)?'
      r'|\|+:?|:?\|+|[-–—]+|/+|\.{2,}|%|N\.?C\.?)$');

  static bool _isChord(String t) => t.isNotEmpty && _chordTok.hasMatch(t);
  static bool _isAnnot(String t) => t.isNotEmpty && _annotTok.hasMatch(t);

  /// Acorde de verdade (não anotação) — usado p/ achar o tom.
  static bool isChordSymbol(String t) => _isChord(t);

  // remove parêntese DESBALANCEADO: "(D9"->"D9", "D4)"->"D4"; mantém "B7(4/9)", "A7(13)".
  static String _fixParens(String t) {
    if (t.startsWith('(') && !t.contains(')')) t = t.substring(1);
    if (t.endsWith(')') && !t.substring(0, t.length - 1).contains('(')) {
      t = t.substring(0, t.length - 1);
    }
    return t;
  }

  static final _ws = RegExp(r'\S+');

  /// Linha só de acordes (e marcações), com pelo menos um acorde de verdade.
  static bool _isChordLine(String line) {
    final toks = _ws.allMatches(line).map((m) => m.group(0)!).toList();
    if (toks.isEmpty) return false;
    var temAcorde = false;
    for (final t in toks) {
      if (_isAnnot(t)) continue;
      if (!_isChord(_fixParens(t))) return false;
      temAcorde = true;
    }
    return temAcorde;
  }

  static SongLine _mergeChordLyric(String chordLine, String lyric) {
    final chords = <Chord>[];
    int maxCol = 0;
    for (final m in _ws.allMatches(chordLine)) {
      final t = m.group(0)!;
      chords.add(Chord(_isAnnot(t) ? t : _fixParens(t), m.start));
      if (m.start > maxCol) maxCol = m.start;
    }
    var lyr = lyric;
    if (lyr.length < maxCol) lyr = lyr.padRight(maxCol);
    return SongLine(lyr, chords);
  }

  // ---- colchetes inline ([G]letra) ----

  // "[Bis]", "[Fim]", "[Ad lib]" no meio da letra são texto, não acorde.
  // Só vira texto o que claramente é palavra; símbolo estranho continua
  // acorde p/ não perder cifra já salva com grafia fora do padrão.
  static final _palavra = RegExp(r'^[A-Za-zÀ-ÿ][a-zà-ÿ]{2,}$');
  static bool _bracketIsText(String c) {
    if (_isChord(_fixParens(c))) return false;
    // palavra ganha de anotação: "[Bis]" no meio da letra é texto, mas
    // "[(2x)]" e "[|]" (que o próprio editor gera) continuam marcação
    return c.trim().isEmpty || c.contains(RegExp(r'\s')) || _palavra.hasMatch(c);
  }

  static final _bracket = RegExp(r'\[([^\]]*)\]');

  static bool _hasInlineChord(String line) =>
      _bracket.allMatches(line).any((m) => !_bracketIsText(m.group(1)!));

  // "[C]Olá [G]mundo" -> SongLine(lyric:'Olá mundo', chords:[C@0, G@4])
  static SongLine parseLine(String raw) {
    final chords = <Chord>[];
    final buf = StringBuffer();
    var i = 0;
    while (i < raw.length) {
      if (raw[i] == '[') {
        final end = raw.indexOf(']', i);
        if (end > i) {
          final c = raw.substring(i + 1, end);
          if (!_bracketIsText(c)) {
            chords.add(Chord(c, buf.length));
            i = end + 1;
            continue;
          }
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

  // ---- limpeza do texto colado ----

  static final _inlineChord = RegExp(r'\[[A-G][#b]?[^\]]*\]');
  static final _sectionHead = RegExp(r'^\s*\[([^\]]+)\]\s*(.*)$');

  static final _htmlTag = RegExp(r'<[^>]*>');
  static final _tagResidue = RegExp(r'^[^<>]*>');
  static final _ccTrailing = RegExp('^\\s*["\']?>\\s*(\\S.*)\$');

  // TAB vira espaço até a próxima parada de 4 colunas — igual na linha de
  // acorde e na de letra, então o alinhamento entre as duas se mantém.
  static String _expandTabs(String s) {
    if (!s.contains('\t')) return s;
    final b = StringBuffer();
    for (final ch in s.split('')) {
      if (ch == '\t') {
        b.write(' ' * (4 - b.length % 4));
      } else {
        b.write(ch);
      }
    }
    return b.toString();
  }

  // Tags viram espaços p/ preservar a coluna do acorde; entidades decodificadas.
  static String _stripTags(String line) =>
      _expandTabs(line.replaceAllMapped(_htmlTag, (m) => ' ' * m.group(0)!.length)
          .replaceAll('&nbsp;', ' ')
          .replaceAll(' ', ' ') // espaço não separável de página web
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'"));

  // Rede de segurança: sobrou fragmento de tag antes de um acorde -> vira espaço.
  static String _stripResidue(String line) {
    final m = _tagResidue.firstMatch(line);
    if (m == null) return line;
    final cand = ' ' * m.group(0)!.length + line.substring(m.end);
    return _isChordLine(cand) ? cand : line;
  }

  // ---- seções escritas em texto ----

  // "Refrão:", "REFRÃO", "1ª Parte", "Parte 2", "Primeira parte", "Intro: C G",
  // "Refrão (2x):". Só vale com palavra-chave conhecida, p/ "E Jesus disse:"
  // continuar sendo letra.
  static final _textHead = RegExp(
      r'^\s*((?:(?:\d+\s*[ªºa°]?|primeira|segunda|terceira|quarta|quinta|sexta|'
      r's[ée]tima|[úu]ltima)\s+)?'
      r'(?:intro(?:du[çc][ãa]o)?|refr[ãa]o|pr[ée][-\s]?refr[ãa]o|coro|ponte|solo|'
      r'final|verso|estrofe|parte|interl[úu]dio|outro|chorus|verse|bridge|riff|'
      r'pré|pre)'
      r'(?:\s*\d+)?(?:\s*\([^)]*\))?)\s*:?(.*)$',
      caseSensitive: false);

  /// [nome, resto] se a linha é um cabeçalho de seção escrito por extenso.
  static List<String>? _textSection(String line) {
    final m = _textHead.firstMatch(line);
    if (m == null) return null;
    final rest = m.group(2)!;
    // resto só pode ser vazio ou acordes ("Intro: C G Am"); se for letra,
    // é verso que começa com "Final", "Ponte"... e não cabeçalho
    if (rest.trim().isNotEmpty && !_isChordLine(rest)) return null;
    return [m.group(1)!.trim(), rest];
  }

  /// [nome, resto] p/ "[Refrão]" ou "[Intro] C G". Não vale quando o
  /// colchete é acorde/marcação: "[|] [C] [|] [G]" é linha ChordPro.
  static List<String>? _bracketSection(String line) {
    final m = _sectionHead.firstMatch(line);
    if (m == null) return null;
    final name = m.group(1)!.trim();
    final rest = m.group(2)!;
    if (_isChord(_fixParens(name)) || _isAnnot(name) || _hasInlineChord(rest)) {
      return null;
    }
    return [name, rest];
  }

  static bool _isSectionLine(String l) =>
      l.startsWith('#') || _bracketSection(l) != null || _textSection(l) != null;

  // ---- metadados ----

  static final _directive = RegExp(r'^\s*\{\s*([A-Za-z_]+)\s*(?::\s*([^}]*))?\}\s*$');
  static final _tomLine = RegExp(r'^\s*tom\s*:\s*([A-G][#b]?m?)\b', caseSensitive: false);
  static final _capoLine =
      RegExp(r'^\s*capo(?:traste)?\b[^0-9\n]{0,20}(\d{1,2})', caseSensitive: false);

  /// Título/artista/tom/capo achados no texto (ChordPro ou "Tom: G").
  static SongMeta detectMeta(String text) {
    final meta = SongMeta();
    for (final raw in text.replaceAll('\r', '').split('\n')) {
      final d = _directive.firstMatch(raw);
      if (d != null) {
        final k = d.group(1)!.toLowerCase();
        final v = (d.group(2) ?? '').trim();
        if (v.isEmpty) continue;
        if (k == 'title' || k == 't') meta.title ??= v;
        if (k == 'subtitle' || k == 'st' || k == 'artist') meta.artist ??= v;
        if (k == 'key') meta.key ??= v;
        if (k == 'capo') meta.capo ??= int.tryParse(v);
        continue;
      }
      final t = _tomLine.firstMatch(raw);
      if (t != null) {
        meta.key ??= t.group(1);
        continue;
      }
      final c = _capoLine.firstMatch(raw);
      if (c != null) meta.capo ??= int.tryParse(c.group(1)!);
    }
    return meta;
  }

  /// Conserta o artefato de copiar/colar do Cifra Club: acorde que cairia
  /// depois do fim da letra vem em linha própria prefixada por `">`, seguido
  /// de uma repetição do trecho inteiro. Ex.:
  ///
  ///     C       G7    C
  ///     Estaremos aqui reunidos
  ///     ">C7
  ///     Estaremos aqui reunidos
  ///
  /// vira `C  G7  C  C7` sobre uma única letra.
  static List<String> _fixCifraClub(List<String> lines) {
    final out = <String>[];
    var i = 0;
    while (i < lines.length) {
      final m = _ccTrailing.firstMatch(lines[i]);
      final sym = m?.group(1)?.trimRight();
      if (sym == null || !_isChordLine(sym)) {
        out.add(lines[i++]);
        continue;
      }

      // letra dona do acorde: última linha de letra antes (pulando
      // linhas em branco e cabeçalhos de seção que também vêm duplicados)
      var j = out.length - 1;
      while (j >= 0 && (out[j].trim().isEmpty || _isSectionLine(out[j]))) {
        j--;
      }
      if (j < 0 || _isChordLine(out[j])) {
        out.add(lines[i++]);
        continue;
      }
      final lyric = out[j];
      final block = out.sublist(j + 1); // o que veio depois da letra

      // confere se logo abaixo vem a repetição: letra + mesmo bloco
      var k = i + 1;
      var dup = k < lines.length && lines[k] == lyric;
      if (dup) {
        k++;
        for (final b in block) {
          if (k >= lines.length || lines[k] != b) {
            dup = false;
            break;
          }
          k++;
        }
      }
      if (!dup) {
        out.add(lines[i++]);
        continue;
      }

      // anexa o acorde no fim da linha de acordes da letra
      final col = lyric.length + 1;
      if (j > 0 && _isChordLine(out[j - 1])) {
        out[j - 1] = out[j - 1].padRight(col) + sym;
      } else {
        out.insert(j, ''.padRight(col) + sym);
      }
      i = k; // descarta a duplicata
    }
    return out;
  }

  static List<Section> importText(String text) {
    final clean = text.replaceAll('\r', '').split('\n').map(_stripTags).toList();
    final raw = _fixCifraClub(clean).map(_stripResidue).toList();
    final sections = <Section>[];
    var cur = Section('', []);
    var started = false;
    // Linha em branco no fim da seção é só o separador: o serializador põe
    // uma entre seções, e sem tirar aqui cada ida e volta texto<->visual no
    // editor somava mais uma.
    void close() {
      while (cur.lines.isNotEmpty &&
          cur.lines.last.chords.isEmpty &&
          cur.lines.last.lyric.trim().isEmpty) {
        cur.lines.removeLast();
      }
      sections.add(cur);
    }

    void newSection(String name) {
      if (started) close();
      cur = Section(name, []);
      started = true;
    }

    bool isLyric(String? l) =>
        l != null &&
        l.trim().isNotEmpty &&
        !_isChordLine(l) &&
        !_isSectionLine(l) &&
        _directive.firstMatch(l) == null;

    for (var i = 0; i < raw.length; i++) {
      var line = raw[i];

      // diretivas ChordPro: {title}, {c: Refrão}, {soc} ... nunca viram letra
      final d = _directive.firstMatch(line);
      if (d != null) {
        final k = d.group(1)!.toLowerCase();
        final v = (d.group(2) ?? '').trim();
        if (const {'comment', 'c', 'ci', 'cb', 'comment_italic', 'comment_box', 'highlight'}
                .contains(k) &&
            v.isNotEmpty) {
          newSection(v);
        } else if (k == 'start_of_chorus' || k == 'soc') {
          newSection(v.isEmpty ? 'Refrão' : v);
        } else if (k == 'start_of_bridge' || k == 'sob') {
          newSection(v.isEmpty ? 'Ponte' : v);
        } else if (k == 'start_of_verse' || k == 'sov') {
          newSection(v);
        }
        continue;
      }

      // "Tom: G" e "Capotraste na 2ª casa" são metadado, não letra
      if (_tomLine.hasMatch(line) || _capoLine.hasMatch(line)) continue;

      if (line.startsWith('#')) {
        newSection(line.substring(1).trim());
        continue;
      }
      final bs = _bracketSection(line);
      if (bs != null) {
        newSection(bs[0]);
        if (bs[1].trim().isEmpty) continue;
        line = bs[1];
      } else {
        final ts = _textSection(line);
        if (ts != null) {
          newSection(ts[0]);
          if (ts[1].trim().isEmpty) continue;
          line = ts[1].trim(); // "Intro: C G" -> acordes a partir da coluna 0
        }
      }

      if (_inlineChord.hasMatch(line) && _hasInlineChord(line)) {
        cur.lines.add(parseLine(line));
        started = true;
        continue;
      }

      if (_isChordLine(line)) {
        final next = i + 1 < raw.length ? raw[i + 1] : null;
        if (isLyric(next)) {
          cur.lines.add(_mergeChordLyric(line, next!));
          i++;
        } else {
          cur.lines.add(_mergeChordLyric(line, ''));
        }
        started = true;
        continue;
      }

      cur.lines.add(parseLine(line)); // texto puro (colchete que é texto fica)
      started = true;
    }
    if (started) close();
    return sections;
  }

  // primeiro acorde de verdade (p/ sugerir tom) — pula (2x), |, N.C.
  static String? firstChord(List<Section> sections) {
    for (final s in sections) {
      for (final l in s.lines) {
        final sorted = [...l.chords]..sort((a, b) => a.idx.compareTo(b.idx));
        for (final c in sorted) {
          if (_isChord(c.sym)) return c.sym;
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
