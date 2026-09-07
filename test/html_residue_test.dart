import 'package:flutter_test/flutter_test.dart';
import 'package:mymusic/core/chord_engine.dart';

void main() {
  test('acorde final do Cifra Club junta na linha e some a duplicata', () {
    const txt = '''
C       G7    C
Estaremos aqui reunidos
">C7
Estaremos aqui reunidos
        F          D
Como estavam em Jerusalém
">G7
Como estavam em Jerusalém
          Dm     G7     C  G/B
Pois só quando vivemos uni_______dos
">Am
Pois só quando vivemos uni_______dos''';

    final lines = ChordEngine.importText(txt).expand((s) => s.lines).toList();

    expect(lines.length, 3, reason: 'duplicatas devem sumir');
    expect(lines[0].lyric.trim(), 'Estaremos aqui reunidos');
    expect(lines[0].chords.map((c) => c.sym).toList(), ['C', 'G7', 'C', 'C7']);
    expect(lines[1].chords.map((c) => c.sym).toList(), ['F', 'D', 'G7']);
    expect(lines[2].chords.map((c) => c.sym).toList(),
        ['Dm', 'G7', 'C', 'G/B', 'Am']);
    // o acorde extra fica depois do fim da letra
    expect(lines[0].chords.last.idx, greaterThan('Estaremos aqui reunidos'.length - 1));
  });

  test('seção duplicada entre letra e acorde final também some', () {
    const txt = '''
           F      G7
É que o Espírito Santo nos vem

[Primeira Parte]

">C
É que o Espírito Santo nos vem

[Primeira Parte]

         G7
Ninguém para esse vento passando''';

    final secs = ChordEngine.importText(txt);
    expect(secs.map((s) => s.name).where((n) => n.isNotEmpty).toList(),
        ['Primeira Parte'], reason: 'seção não pode duplicar');

    final lines = secs.expand((s) => s.lines).where((l) => l.lyric.trim().isNotEmpty).toList();
    expect(lines.length, 2);
    expect(lines[0].chords.map((c) => c.sym).toList(), ['F', 'G7', 'C']);
    expect(lines[1].chords.map((c) => c.sym).toList(), ['G7']);
  });

  test('tag HTML completa é removida preservando coluna', () {
    final secs = ChordEngine.importText('<b>C</b>      <b>G7</b>\nOlá mundo');
    expect(secs.first.lines.single.chords.map((c) => c.sym).toList(), ['C', 'G7']);
  });

  test('letra normal com ">" não é destruída', () {
    final secs = ChordEngine.importText('Ele disse: 5 > 3 sempre');
    expect(secs.first.lines.single.lyric, 'Ele disse: 5 > 3 sempre');
  });

  test('">" sem duplicata vira acorde mesmo assim', () {
    final lines =
        ChordEngine.importText('">C7\nEstaremos aqui').expand((s) => s.lines).toList();
    expect(lines.single.chords.single.sym, 'C7');
  });
}
