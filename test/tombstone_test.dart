// Exclusão via sync: sem lápide, o sync baixava a música apagada de volta.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymusic/data/store.dart';
import 'package:mymusic/models/song.dart';

Song s(String id, DateTime at) => Song(id: id, title: id, updatedAt: at);

void main() {
  final ontem = DateTime.now().subtract(const Duration(days: 1));

  test('excluir aqui e sincronizar não traz de volta', () {
    final tablet = AppState()..songs.addAll([s('a', ontem), s('b', ontem)]);
    final drive = tablet.exportJson(); // Drive ainda tem as duas
    tablet.deleteSong('a');
    tablet.importJson(drive, origem: 'drive'); // sync: baixa e mescla
    expect(tablet.songs.map((x) => x.id), ['b'], reason: 'a ressuscitou');
  });

  test('exclusão feita em outro aparelho chega aqui', () {
    final tablet = AppState()..songs.addAll([s('a', ontem), s('b', ontem)]);
    final web = AppState()..songs.addAll([s('a', ontem), s('b', ontem)]);
    web.deleteSong('b');
    tablet.importJson(web.exportJson(), origem: 'drive');
    expect(tablet.songs.map((x) => x.id), ['a']);
    expect(tablet.audit.first.details.join(' '), contains('Excluídos em outro aparelho: 1'));
  });

  test('editada DEPOIS de excluída em outro lugar sobrevive', () {
    final a = AppState()..songs.add(s('x', ontem));
    final b = AppState()..songs.add(s('x', ontem));
    a.deleteSong('x');
    b.songs.first.updatedAt = DateTime.now().add(const Duration(minutes: 1));
    a.importJson(b.exportJson(), origem: 'drive');
    expect(a.songById('x'), isNotNull);
  });

  test('lápide sobe junto no export e repertório também', () {
    final a = AppState()..setlists.add(Setlist(id: 'r', name: 'Missa', updatedAt: ontem));
    a.deleteSetlist('r');
    final j = jsonDecode(a.exportJson()) as Map;
    expect((j['deleted'] as Map).keys, contains('setlist:r'));
    final b = AppState()..setlists.add(Setlist(id: 'r', name: 'Missa', updatedAt: ontem));
    b.importJson(a.exportJson());
    expect(b.setlists, isEmpty);
  });
}
