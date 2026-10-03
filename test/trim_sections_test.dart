import 'package:flutter_test/flutter_test.dart';
import 'package:mymusic/core/chord_engine.dart';
import 'package:mymusic/models/song.dart';

void main() {
  test('tira só as linhas em branco do fim de cada seção', () {
    final secs = [
      Section('Intro', [
        SongLine('  ', [Chord('D9', 0)]),
        SongLine('', []),
        SongLine('  ', [Chord('C9', 0)]),
        SongLine('', []),
        SongLine('   ', []),
        SongLine('', []),
      ]),
      Section('', [SongLine('Glória', []), SongLine('', []), SongLine('', []), SongLine('A Deus', [])]),
    ];
    expect(ChordEngine.trimSectionEnds(secs), isTrue);
    expect(secs[0].lines.length, 3, reason: 'a linha em branco do meio fica');
    expect(secs[1].lines.length, 4, reason: 'pulo de 2 linhas entre grupos fica');
    expect(ChordEngine.trimSectionEnds(secs), isFalse);
  });
}
