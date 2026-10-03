// Padrões reais achados na biblioteca do usuário (gravados antes de 7M ser
// reconhecido): linha de acorde salva como letra.
import 'package:flutter_test/flutter_test.dart';
import 'package:mymusic/core/chord_engine.dart';
import 'package:mymusic/models/song.dart';

SongLine t(String s) => SongLine(s, []);

void main() {
  test('linha de acordes antiga vira acorde em cima da letra de baixo', () {
    final secs = [
      Section('Intro', [t('Bm7  G7M'), t('Bm7       A      G7M')]),
      Section('', [t('D/F#      G7M'), t('É digno que a esposa'), t('Tudo bem')]),
    ];
    expect(ChordEngine.repairChordLines(secs), 3);
    // intro: duas linhas só de acorde, sem letra embaixo
    expect(secs[0].lines.map((l) => l.chords.map((c) => c.sym).toList()),
        [['Bm7', 'G7M'], ['Bm7', 'A', 'G7M']]);
    final l = secs[1].lines.first;
    expect(l.lyric.trimRight(), 'É digno que a esposa');
    expect(l.chords.map((c) => '${c.sym}@${c.idx}'), ['D/F#@0', 'G7M@10']);
    expect(secs[1].lines[1].lyric, 'Tudo bem', reason: 'resto intacto');
  });

  test('não confunde palavra com acorde', () {
    final secs = [Section('', [t('Em'), t('A'), t('E Jesus disse'), t('Glória')])];
    expect(ChordEngine.repairChordLines(secs), 0);
  });

  test('idempotente', () {
    final secs = [Section('', [t('G   F7M'), t('Por ti')])];
    expect(ChordEngine.repairChordLines(secs), 1);
    expect(ChordEngine.repairChordLines(secs), 0);
  });
}
