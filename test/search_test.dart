import 'package:flutter_test/flutter_test.dart';
import 'package:mymusic/core/chord_engine.dart';
import 'package:mymusic/core/search.dart';
import 'package:mymusic/models/song.dart';

Song s(String id, String title, {String artist = '', String letra = ''}) => Song(
    id: id, title: title, artist: artist, sections: ChordEngine.importText(letra));

void main() {
  final musicas = [
    s('1', 'Teu Óleo Santo', letra: 'C\nTeu óleo santo que marcou a minha fronte'),
    s('2', 'Glória a Deus Nas Alturas', artist: 'Eliana Ribeiro',
        letra: 'G\nE paz na Terra aos homens por Ele amados'),
    s('3', 'Cordeiro de Deus', letra: 'G\nTende piedade, piedade de nós'),
  ];
  List<String> ids(String q) => SongSearch.run(musicas, q).map((h) => h.song.id).toList();

  test('sem acento acha com acento', () {
    expect(ids('oleo'), ['1']);
    expect(ids('GLORIA'), ['2']);
  });
  test('acha pelo trecho da letra e devolve a linha', () {
    final h = SongSearch.run(musicas, 'piedade de nos').single;
    expect(h.song.id, '3');
    expect(h.inLyric, isTrue);
    expect(h.snippet, 'Tende piedade, piedade de nós');
  });
  test('nome vem antes de letra', () {
    // "deus" está no título da 2 e da 3
    expect(ids('deus'), ['2', '3']);
  });
  test('várias palavras: todas no título/artista', () {
    expect(ids('gloria eliana'), ['2']);
  });
  test('vazio devolve tudo', () => expect(ids('  '), ['1', '2', '3']));
}
