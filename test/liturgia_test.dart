import 'package:flutter_test/flutter_test.dart';
import 'package:mymusic/core/liturgia.dart';
import 'package:mymusic/models/song.dart';
import 'package:mymusic/ui/widgets/chord_chart.dart';

void main() {
  DateTime d(int y, int m, int dd) => DateTime(y, m, dd);

  test('Páscoa', () {
    expect(Liturgia.pascoa(2025), DateTime.utc(2025, 4, 20));
    expect(Liturgia.pascoa(2026), DateTime.utc(2026, 4, 5));
    expect(Liturgia.pascoa(2027), DateTime.utc(2027, 3, 28));
  });

  test('Advento e Batismo', () {
    expect(Liturgia.advento(2025), DateTime.utc(2025, 11, 30));
    expect(Liturgia.advento(2026), DateTime.utc(2026, 11, 29));
    expect(Liturgia.batismo(2025), DateTime.utc(2025, 1, 12));
    expect(Liturgia.batismo(2026), DateTime.utc(2026, 1, 11));
    // Epifania 7/1/2024 (domingo) -> Batismo na segunda, 8/1
    expect(Liturgia.batismo(2024), DateTime.utc(2024, 1, 8));
  });

  test('tempo da data', () {
    expect(Liturgia.temposDe(d(2026, 11, 28)), ['Tempo Comum']);
    expect(Liturgia.temposDe(d(2026, 11, 29)), ['Advento']);
    expect(Liturgia.temposDe(d(2026, 12, 24)), ['Advento']);
    expect(Liturgia.temposDe(d(2026, 12, 25)), ['Natal']);
    expect(Liturgia.temposDe(d(2026, 1, 11)), ['Natal']);
    expect(Liturgia.temposDe(d(2026, 1, 12)), ['Tempo Comum']);
    expect(Liturgia.temposDe(d(2026, 2, 17)), ['Tempo Comum']);
    expect(Liturgia.temposDe(d(2026, 2, 18)), ['Quaresma']); // Cinzas
    expect(Liturgia.temposDe(d(2026, 3, 29)), ['Semana Santa', 'Quaresma']);
    expect(Liturgia.temposDe(d(2026, 4, 5)), ['Páscoa']);
    expect(Liturgia.temposDe(d(2026, 5, 24)), ['Pentecostes', 'Páscoa']);
    expect(Liturgia.temposDe(d(2026, 5, 25)), ['Tempo Comum']);
  });

  test('ordem da Missa', () {
    expect(Liturgia.ordem('Entrada'), lessThan(Liturgia.ordem('Comunhão')));
    expect(Liturgia.ordem(null), Liturgia.momentos.length);
  });

  test('uso das músicas pelos repertórios com data', () {
    final sls = [
      Setlist(id: 'a', name: 'A', songIds: ['x', 'y'], date: d(2026, 9, 6)),
      Setlist(id: 'b', name: 'B', songIds: ['x'], date: d(2026, 9, 20)),
      Setlist(id: 'c', name: 'C', songIds: ['x', 'z'], date: d(2026, 10, 11)),
      Setlist(id: 'e', name: 'sem data', songIds: ['w']),
    ];
    final u = UsoMusicas.calcula(sls, ate: d(2026, 10, 3));
    expect(u['x']!.vezes, 2);
    expect(u['x']!.ultima, DateTime.utc(2026, 9, 20));
    expect(u['y']!.vezes, 1);
    expect(u.containsKey('z'), isFalse); // futuro
    expect(u.containsKey('w'), isFalse); // sem data
    expect(UsoMusicas.calcula(sls, ate: d(2026, 10, 3), exceto: 'b')['x']!.ultima,
        DateTime.utc(2026, 9, 6));
    expect(UsoMusicas.quando(d(2026, 9, 20), hoje: d(2026, 10, 3)), 'há 1 semana');
    expect(UsoMusicas.quando(d(2026, 10, 3), hoje: d(2026, 10, 3)), 'hoje');
  });

  test('campos novos sobrevivem ao JSON', () {
    final s = Song(id: '1', title: 't', scrollSpeed: 40, tempos: ['Quaresma'], momentos: ['Entrada']);
    final r = Song.fromJson(s.toJson());
    expect(r.scrollSpeed, 40);
    expect(r.tempos, ['Quaresma']);
    expect(r.momentos, ['Entrada']);
    expect(Song.fromJson(Song(id: '2', title: 'u').toJson()).scrollSpeed, 0);
    final sl = Setlist(id: 's', name: 'n', moments: {'1': 'Comunhão'});
    expect(Setlist.fromJson(sl.toJson()).moments, {'1': 'Comunhão'});
    final st = AppSettings(lyricsOnly: true);
    expect(AppSettings.fromJson(st.toJson()).lyricsOnly, isTrue);
  });

  test('só letra: tira linha só de acorde e seção que ficou vazia', () {
    final song = Song(id: '1', title: 't', sections: [
      Section('Intro', [SongLine('', [Chord('G', 0), Chord('D', 4)])]),
      Section('', [
        SongLine('   Eu te louvo', [Chord('G', 3)]),
        SongLine('', []),
        SongLine('', []),
        SongLine('Senhor', []),
        SongLine('', []),
      ]),
    ]);
    final l = ChordChart.letra(song);
    expect(l.length, 1);
    expect(l.first.lines.map((x) => x.lyric), ['Eu te louvo', '', 'Senhor']);
  });
}
