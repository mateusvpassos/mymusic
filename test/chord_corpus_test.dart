// Corpus de cifras do mundo real: formatos que aparecem colando do Cifra
// Club, de PDF de folheto de missa, de WhatsApp, de arquivo ChordPro etc.
import 'package:flutter_test/flutter_test.dart';
import 'package:mymusic/core/chord_engine.dart';
import 'package:mymusic/models/song.dart';

List<SongLine> _lines(String txt) =>
    ChordEngine.importText(txt).expand((s) => s.lines).toList();

List<String> _chords(String chordLine, [String lyric = 'Letra qualquer aqui embaixo de tudo']) =>
    _lines('$chordLine\n$lyric').first.chords.map((c) => c.sym).toList();

List<String> _names(String txt) =>
    ChordEngine.importText(txt).map((s) => s.name).where((n) => n.isNotEmpty).toList();

void main() {
  group('acordes reconhecidos numa linha de acordes', () {
    final casos = <String, List<String>>{
      'D7/9   A7/13   G7/4': ['D7/9', 'A7/13', 'G7/4'],
      'Bm7(b5)   F#m7(b5)   E7(#9)': ['Bm7(b5)', 'F#m7(b5)', 'E7(#9)'],
      'Bb7M   Eb7M(9)   C7(9/13)': ['Bb7M', 'Eb7M(9)', 'C7(9/13)'],
      'Dsus4   D4   Gadd9   C(add9)': ['Dsus4', 'D4', 'Gadd9', 'C(add9)'],
      'Am7/G   C/E   F/A   Bb/C': ['Am7/G', 'C/E', 'F/A', 'Bb/C'],
      'G6   Cº   C°7   Cdim7   C+   Caug': ['G6', 'Cº', 'C°7', 'Cdim7', 'C+', 'Caug'],
      'A5   E5   Cmaj7   CmM7   Dm6   G13': ['A5', 'E5', 'Cmaj7', 'CmM7', 'Dm6', 'G13'],
      'Bø   Bø7   F7M/A': ['Bø', 'Bø7', 'F7M/A'],
      'A7(b13)   Em7(11)   F#7(13)': ['A7(b13)', 'Em7(11)', 'F#7(13)'],
    };
    casos.forEach((linha, esperado) {
      test(linha, () => expect(_chords(linha), esperado));
    });
  });

  group('anotações não estragam a linha de acordes', () {
    test('repetição (2x) no fim', () {
      expect(_chords('C   G   Am   F   (2x)'), ['C', 'G', 'Am', 'F', '(2x)']);
    });
    test('x2 / 2x', () {
      expect(_chords('C   G   x2'), ['C', 'G', 'x2']);
      expect(_chords('C   G   2x'), ['C', 'G', '2x']);
    });
    test('barras de compasso', () {
      expect(_chords('| C | G | Am | F |').where((c) => c != '|'),
          ['C', 'G', 'Am', 'F']);
    });
    test('traços entre acordes', () {
      expect(_chords('C - G - Am - F').where((c) => c != '-'),
          ['C', 'G', 'Am', 'F']);
    });
    test('(Bis) e N.C.', () {
      expect(_chords('C   G   D   (Bis)'), ['C', 'G', 'D', '(Bis)']);
      expect(_chords('N.C.   G   D'), ['N.C.', 'G', 'D']);
    });
    test('linha só de anotação não vira acorde', () {
      // "(2x)" sozinho embaixo da letra é marcação, não linha de acordes
      final l = _lines('Glória a Deus nas alturas\n(2x)');
      expect(l.every((x) => x.chords.isEmpty), isTrue);
    });
  });

  group('cabeçalho de seção', () {
    test('"Refrão:" sozinho', () {
      expect(_names('Refrão:\nC  G\nLetra'), ['Refrão']);
    });
    test('REFRÃO em caixa alta', () {
      expect(_names('REFRÃO\nC  G\nLetra'), ['REFRÃO']);
    });
    test('1ª Parte / 2ª PARTE', () {
      expect(_names('1ª Parte\nC\nA\n\n2ª PARTE\nG\nB'), ['1ª Parte', '2ª PARTE']);
    });
    test('Intro: com acordes na mesma linha', () {
      final secs = ChordEngine.importText('Intro: C  G  Am  F\n\nRefrão:\nC\nLetra');
      expect(secs.first.name, 'Intro');
      expect(secs.first.lines.first.chords.map((c) => c.sym), ['C', 'G', 'Am', 'F']);
    });
    test('letra terminando em dois pontos continua letra', () {
      expect(_names('E Jesus disse:\nVinde a mim'), isEmpty);
      expect(_lines('E Jesus disse:\nVinde a mim').first.lyric, 'E Jesus disse:');
    });
    test('Refrão (2x):', () {
      expect(_names('Refrão (2x):\nC\nLetra'), ['Refrão (2x)']);
    });
  });

  group('ChordPro', () {
    const cp = '''
{title: Noite Feliz}
{key: G}
{c: Primeira parte}
[G]Noite fe[D]liz
{soc}
[C]Glória a [G]Deus
{eoc}
''';
    test('diretivas não viram letra', () {
      final txt = _lines(cp).map((l) => l.lyric).join('|');
      expect(txt, isNot(contains('{')));
    });
    test('comentário e refrão viram seção', () {
      expect(_names(cp), containsAll(['Primeira parte', 'Refrão']));
    });
    test('detecta título e tom', () {
      final meta = ChordEngine.detectMeta(cp);
      expect(meta.title, 'Noite Feliz');
      expect(meta.key, 'G');
    });
  });

  group('metadados no texto colado', () {
    test('Tom: e Capo', () {
      final m = ChordEngine.detectMeta('Tom: Em\nCapotraste na 2ª casa\n\nEm  C\nLetra');
      expect(m.key, 'Em');
      expect(m.capo, 2);
    });
    test('linha "Tom:" não aparece como letra', () {
      final l = _lines('Tom: Em\n\nEm   C\nLetra da música');
      expect(l.any((x) => x.lyric.startsWith('Tom:')), isFalse);
    });
  });

  group('colchete que não é acorde', () {
    test('[Bis] no meio da letra fica como texto', () {
      final l = _lines('Glória a Deus [Bis]').single;
      expect(l.chords, isEmpty);
      expect(l.lyric, 'Glória a Deus [Bis]');
    });
    test('[G] no meio da letra continua acorde', () {
      final l = _lines('Glória a [G]Deus').single;
      expect(l.chords.single.sym, 'G');
      expect(l.lyric, 'Glória a Deus');
    });
  });

  group('espaçamento esquisito de copiar/colar', () {
    test('espaço não separável (NBSP) da web', () {
      final l = _lines('C\u00a0\u00a0\u00a0\u00a0G\nOlá mundo lindo').single;
      expect(l.chords.map((c) => c.idx), [0, 5]);
      expect(l.lyric, 'Olá mundo lindo');
    });
    test('TAB vira espaço nas duas linhas igual', () {
      final l = _lines('C\tG\nab\tcd').single;
      // acorde G tem que ficar em cima do "c"
      expect(l.lyric.indexOf('c'), l.chords[1].idx);
    });
  });

  group('transposição', () {
    String t(String c, int s) => ChordEngine.transposeChord(c, s, false);
    test('tensão com barra não é baixo', () {
      expect(t('D7/9', 2), 'E7/9');
      expect(t('A7/13', -2), 'G7/13');
    });
    test('baixo continua transpondo', () {
      expect(t('Am7/G', 2), 'Bm7/A');
      expect(t('F#m7(b5)/E', 1), 'Gm7(b5)/F');
    });
    test('enarmônicos raros', () {
      expect(t('Cb', 1), 'C');
      expect(t('E#', 1), 'F#');
      expect(t('Fb', 0), 'E');
    });
    test('meio-diminuto', () => expect(t('Bø', 2), 'C#ø'));
    test('anotações ficam intactas', () {
      expect(t('(2x)', 3), '(2x)');
      expect(t('N.C.', 3), 'N.C.');
      expect(t('|', 3), '|');
    });
    test('parênteses com barra dentro', () => expect(t('B7(4/9)', 1), 'C7(4/9)'));
  });

  group('sugestão de tom', () {
    test('ignora anotação antes do primeiro acorde', () {
      final secs = ChordEngine.importText('N.C.   Em   C\nLetra da música aqui');
      expect(ChordEngine.suggestKey(secs), 'Em');
    });
  });

  group('ida e volta pelo editor (texto ChordPro)', () {
    test('serializar e reimportar não perde nada', () {
      const txt = '''
#Refrão
C       G7    C    C7
Estaremos aqui reunidos
        F          D  G7
Como estavam em Jerusalém

#Primeira Parte
| C | G | Am | F |   (2x)
''';
      final a = ChordEngine.importText(txt);
      final b = ChordEngine.importText(ChordEngine.serializeSections(a));
      String dump(List<Section> s) => s
          .map((x) => '${x.name}:${x.lines.map((l) => '${l.lyric.trimRight()}'
              '${l.chords.map((c) => '${c.sym}@${c.idx}').join(',')}').join(';')}')
          .join('/');
      expect(dump(b), dump(a));
    });
  });
}
