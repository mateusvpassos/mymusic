import 'package:flutter_test/flutter_test.dart';
import 'package:mymusic/core/chord_engine.dart';
import 'package:mymusic/models/song.dart';

void main() {
  test('parse + serialize roundtrip', () {
    const raw = 'O [G]esplendor de um [D]Rei';
    final line = ChordEngine.parseLine(raw);
    expect(line.lyric, 'O esplendor de um Rei');
    expect(line.chords.length, 2);
    expect(line.chords[0].sym, 'G');
    expect(ChordEngine.serializeLine(line), raw);
  });

  test('transpose chord up 2 semitones', () {
    expect(ChordEngine.transposeChord('G', 2, false), 'A');
    expect(ChordEngine.transposeChord('Em7', 2, false), 'F#m7');
    expect(ChordEngine.transposeChord('A/C#', 2, false), 'B/D#');
  });

  test('import chord-over-lyric (Cifra Club style)', () {
    const t = '[Intro] Bm  B7(4/9)  Bm  B7(4/9)\n'
        '\n'
        '  Bm7            F#m7  G9            Bm7 A9\n'
        'Santo, Santo, Santo, Senhor Deus do universo\n';
    final secs = ChordEngine.importText(t);
    // primeira seção = Intro, standalone chord line
    expect(secs.first.name, 'Intro');
    expect(secs.first.lines.first.chords.map((c) => c.sym).toList(),
        ['Bm', 'B7(4/9)', 'Bm', 'B7(4/9)']);
    // linha com letra + acordes posicionados por coluna
    final lyrLine = secs.last.lines.firstWhere((l) => l.lyric.contains('Santo'));
    expect(lyrLine.chords.first.sym, 'Bm7');
    expect(lyrLine.chords.first.idx, 2); // coluna do "Bm7"
    expect(lyrLine.chords.any((c) => c.sym == 'F#m7'), true);
  });

  test('import recognizes G7M and parenthesized chords', () {
    const t = '        G7M\n'
        'É digno que a esposa\n'
        '\n'
        'D  (D9 D4)\n'
        'qualquer letra\n';
    final secs = ChordEngine.importText(t);
    final all = secs.expand((s) => s.lines).expand((l) => l.chords).map((c) => c.sym).toList();
    expect(all.contains('G7M'), true);
    expect(all.contains('D9'), true);
    expect(all.contains('D4'), true);
    // parêntese desbalanceado removido
    expect(all.any((c) => c.contains('(') || c.contains(')')), false);
  });

  test('balanced parens chord stays intact', () {
    final l = ChordEngine.importText('B7(4/9)\nletra').expand((s) => s.lines).first;
    expect(l.chords.first.sym, 'B7(4/9)');
  });

  test('transpose minor key label', () {
    final s = Song(id: '1', title: 't', key: 'Bm', sections: [
      Section('', [ChordEngine.parseLine('[Bm]a [B7]b')]),
    ]);
    final up = ChordEngine.transposeSong(s, 2);
    expect(up.key, 'C#m');
    expect(up.sections[0].lines[0].chords[0].sym, 'C#m');
  });

  test('transpose song updates key', () {
    final s = Song(id: '1', title: 't', key: 'C', sections: [
      Section('', [ChordEngine.parseLine('[C]hello [G]world')]),
    ]);
    final up = ChordEngine.transposeSong(s, 2);
    expect(up.key, 'D');
    expect(up.sections[0].lines[0].chords[0].sym, 'D');
  });
}
