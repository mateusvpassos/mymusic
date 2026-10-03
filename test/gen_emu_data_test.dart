// Ferramenta (não é teste de verdade): gera build/emu_song.json com a cifra
// difícil do corpus, p/ conferir a renderização no emulador.
// ATENÇÃO: só carregue em emulador com o Google Drive DESLOGADO no app.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymusic/core/chord_engine.dart';
import 'package:mymusic/models/song.dart';

void main() {
  test('gera build/emu_song.json', () async {
    final s = Song(
        id: 'teste-dificil',
        title: 'TESTE cifra difícil',
        artist: 'corpus',
        key: 'G',
        sections: ChordEngine.importText(File('test/fixtures/dificil.txt').readAsStringSync()),
        updatedAt: DateTime.now());
    final out = File('build/emu_song.json');
    await out.create(recursive: true);
    await out.writeAsString(jsonEncode(s.toJson()));
  });
}
