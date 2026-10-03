// Gera uma biblioteca de teste p/ carregar no emulador (não é teste de verdade:
// só escreve build/emu_data.json no formato do app).
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymusic/core/chord_engine.dart';
import 'package:mymusic/models/song.dart';

void main() {
  test('gera build/emu_data.json', () async {
    String fx(String f) => File('test/fixtures/$f').readAsStringSync();
    final songs = <Song>[];
    void add(String id, String title, String artist, String key, String txt, {int capo = 0}) {
      final s = Song(
          id: id,
          title: title,
          artist: artist,
          key: key,
          capo: capo,
          sections: ChordEngine.importText(txt),
          updatedAt: DateTime(2026, 9, 1));
      songs.add(s);
    }

    add('estaremos', 'Estaremos Aqui Reunidos', 'Padre Zezinho', 'C', fx('estaremos.txt'));
    add('oleo', 'Teu Óleo Santo', '', 'C', fx('oleo.txt'));
    add('maria', 'Maria de Nazaré', 'Padre Zezinho', 'D', fx('maria.txt'));
    add('dificil', 'Cifra difícil (teste)', 'corpus', 'G', fx('dificil.txt'), capo: 2);
    final sl = Setlist(
        id: 'crisma',
        name: 'Missa Crisma (teste)',
        songIds: ['estaremos', 'oleo', 'maria', 'dificil'],
        updatedAt: DateTime(2026, 9, 1));
    final out = File('build/emu_data.json');
    await out.create(recursive: true);
    await out.writeAsString(jsonEncode({
      'songs': songs.map((s) => s.toJson()).toList(),
      'setlists': [sl.toJson()],
      'settings': {'dark': false, 'fontScale': 1.0, 'pageStep': 0.4},
    }));
  });
}
