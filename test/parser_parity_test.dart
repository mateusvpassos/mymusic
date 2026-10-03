// Gera a saída do parser p/ o fixture compartilhado com o editor web
// (mymusic-web/scripts/parity.ts compara as duas).
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymusic/core/chord_engine.dart';

String dump(String txt) => ChordEngine.importText(txt)
    .map((s) => '${s.name}:${s.lines.map((l) => '${l.lyric.trimRight()}'
        '<${l.chords.map((c) => '${c.sym}@${c.idx}').join(',')}>').join(';')}')
    .join('/');

void main() {
  test('gera saída de paridade', () async {
    final cases = (jsonDecode(
            await File('test/fixtures/parser_cases.json').readAsString()) as List)
        .cast<String>();
    final out = {
      'dumps': cases.map(dump).toList(),
      'meta': cases.map((c) {
        final m = ChordEngine.detectMeta(c);
        return '${m.title}|${m.artist}|${m.key}|${m.capo}';
      }).toList(),
      'keys': cases.map((c) => '${ChordEngine.suggestKey(ChordEngine.importText(c))}').toList(),
      'transp': [
        for (final c in ['D7/9', 'A7/13', 'Am7/G', 'F#m7(b5)/E', 'Cb', 'E#', 'Bø', '(2x)', 'N.C.', '|', 'B7(4/9)', 'Bb7M(9)'])
          for (final s in [-3, 1, 2])
            ChordEngine.transposeChord(c, s, false)
      ],
    };
    final f = File('build/parser_dart.json');
    await f.create(recursive: true);
    await f.writeAsString(const JsonEncoder.withIndent(' ').convert(out));
    expect(out['dumps'], hasLength(cases.length));
  });
}
