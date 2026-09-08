// Caso real: cifra do Cifra Club como o usuário colou (com o artefato `">`),
// usada p/ conferir o encaixe do PDF de verdade e não só em música sintética.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymusic/core/chord_engine.dart';
import 'package:mymusic/core/pdf_export.dart';
import 'package:mymusic/models/song.dart';

const _estaremos = '''
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
Pois só quando vivemos uni_______dos
           F      G7
É que o Espírito Santo nos vem

[Primeira Parte]

">C
É que o Espírito Santo nos vem

[Primeira Parte]

         G7
Ninguém para esse vento passando
">C
Ninguém para esse vento passando
         E       E7
Ninguém vê e ele sopra onde quer
">Am
Ninguém vê e ele sopra onde quer
         F           Fm      C
Força igual tem o Espírito quando
">Am
Força igual tem o Espírito quando
         Dm      G7
Faz a igreja de Cristo crescer

[Refrão]

">C
Faz a igreja de Cristo crescer

[Refrão]

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
Pois só quando vivemos uni_______dos
           F      G7
É que o Espírito Santo nos vem

">C
É que o Espírito Santo nos vem

[Segunda Parte]

          G7
Feita de homens, a igreja é divina
">C
Feita de homens, a igreja é divina
          E     E7
Pois o Espírito Santo a conduz
">Am
Pois o Espírito Santo a conduz
         F          Fm        C
Como um fogo que aquece e ilumina
">Am
Como um fogo que aquece e ilumina
         Dm         G7
Que é pureza, que é vida, que é luz

[Refrão]

">C
Que é pureza, que é vida, que é luz

[Refrão]

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
Pois só quando vivemos uni_______dos
           F      G7
É que o Espírito Santo nos vem

[Terceira Parte]

">C
É que o Espírito Santo nos vem

[Terceira Parte]

      G7
Sua imagem são línguas ardentes
">C
Sua imagem são línguas ardentes
         E      E7
Pois o amor é comunicação
">Am
Pois o amor é comunicação
        F        Fm       C
E é preciso que todas as gentes
">Am
E é preciso que todas as gentes
         Dm     G7
Saibam quanto felizes serão

[Refrão]

">C
Saibam quanto felizes serão
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final song = Song(
    id: 'real',
    title: 'Estaremos Aqui Reunidos',
    key: 'C',
    sections: ChordEngine.importText(_estaremos),
  );

  test('a cifra real ganha 2 colunas e fonte bem maior', () {
    final fit = PdfExport.debugFit(song);
    // ignore: avoid_print
    print('real -> colunas=${fit[0]} fonte=${fit[1].toStringAsFixed(1)} '
        'ocupação=${fit[2].toStringAsFixed(2)} overflow=${fit[3]}');

    expect(fit[0], 2, reason: 'em 1 coluna sobrava metade da largura');
    expect(fit[1], greaterThan(11.0), reason: 'antes saía em 9.5');
    expect(fit[2], lessThanOrEqualTo(1.0));
    expect(fit[3], 0, reason: 'tem que caber numa página');
  });

  test('gera o PDF real p/ inspeção', () async {
    final doc = await PdfExport.setlistDoc('Missa Crisma', [song]);
    final out = File('build/test-real.pdf');
    await out.create(recursive: true);
    await out.writeAsBytes(await doc.save());
    expect(doc.document.pdfPageList.pages.length, 2);
  });

  test('letra do refrão sai em negrito, letra normal não', () {
    final rows = PdfExport.debugRows(song);
    final refrao = rows.where((r) => r.kind == 2 && r.refrao);
    final normal = rows.where((r) => r.kind == 2 && !r.refrao);
    expect(refrao, isNotEmpty);
    expect(normal, isNotEmpty);
    expect(refrao.any((r) => r.text.contains('Estaremos aqui reunidos')), isTrue);
  });
}
