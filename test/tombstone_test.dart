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
    expect(tablet.audit.first.details.join(' '), contains('Excluídas em outro aparelho: b'));
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

  test('sync sem novidade não grava nada no histórico', () {
    final a = AppState()..songs.add(s('a', ontem));
    final drive = a.exportJson();
    var avisos = 0;
    a.addListener(() => avisos++);
    a.importJson(drive, origem: 'drive');
    a.importJson(drive, origem: 'drive');
    expect(a.audit, isEmpty);
    expect(avisos, 0, reason: 'nem notifica (regravar dispararia outro sync)');
  });

  test('sync com novidade diz o quê, pelo nome', () {
    final tablet = AppState()..songs.add(Song(id: 'a', title: 'Santo', updatedAt: ontem));
    final web = AppState()
      ..songs.addAll([
        Song(id: 'a', title: 'Santo', capo: 2, updatedAt: DateTime.now()),
        Song(id: 'n', title: 'Ave Maria', updatedAt: DateTime.now()),
      ]);
    tablet.importJson(web.exportJson(), origem: 'drive');
    final d = tablet.audit.single.details.join(' | ');
    expect(d, contains('Músicas novas: Ave Maria'));
    expect(d, contains('Músicas alteradas: Santo'));
  });
}
