// Casos reais do repertório "Missa Crisma", reconstruídos a partir do PDF que
// o app gerou no tablet. Servem p/ travar o comportamento do layout de coluna.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymusic/core/chord_engine.dart';
import 'package:mymusic/core/pdf_export.dart';
import 'package:mymusic/models/song.dart';

// 5 seções nomeadas.
const _estaremos = '''
#Refrão
       C       G     C
Estaremos aqui reunidos
        F       D     G
Como estavam em Jerusalém
          Dm      G      C  Am
Pois só quando vivemos unidos
           F      G         C
É que o Espírito Santo nos vem

#Primeira Parte
        G                   C
Ninguém para esse vento passando
        E                    Am
Ninguém vê e ele sopra onde quer
        F         Fm        C
Força igual tem o Espírito quando
        Dm        G       C    G7
Faz a igreja de Cristo crescer

#Segunda Parte
        G                      C
Feita de homens, a igreja é divina
         E                Am
Pois o Espírito Santo a conduz
         F         Fm         C
Como um fogo que aquece e ilumina
        Dm           G           C  G7
Que é pureza, que é vida, que é luz

#Terceira Parte
      G                   C
Sua imagem são línguas ardentes
       E             Am
Pois o amor é comunicação
       F                   C
E é preciso que todas as gentes
        Dm       G       C  G7
Saibam quanto felizes serão

#Quarta Parte
            G                    C
Quando o Espírito espalma suas graças
        E              Am
Faz dos povos um só coração
            F                   C
Cresce a igreja, onde todas as raças
      Dm          G          C  G7
Um só Deus, um só Pai, louvarão
''';

// Sem nenhuma seção nomeada: os grupos são marcados pulando linha.
const _maria = '''
  D          Em     A7         D
Maria de Nazaré, Maria me cativou
                       Em
Fez mais forte a minha fé
   A7              D
E por filho me adotou

    Am7       D7    G
Às vezes eu paro e fico a pensar
  Gm7             Gbm7
E sem perceber me vejo a rezar
  Bm7             Em
E meu coração se põe a cantar
     A7            D
Pra virgem de Nazaré

  Am7       D7    G
Menina que Deus amou e escolheu
    Gm7              Gbm7
Pra mãe de Jesus, o filho de Deus
 Bm7                Em
Maria que o povo inteiro elegeu
    A7            D  A7
Senhora e mãe do Céu

D Bm7   Em  A7     D
Ave  Maria, Ave Maria
Bm7   Em    A7       D  A7
Ave Maria, mãe de Jesus

  D                 Em
Maria que eu quero bem
   A7           D
E de tanto amor esperar
  Bm7             Em
Sei que a minha vida um dia vai mudar
     A7            D
Pra virgem de Nazaré
''';

// Linhas longas (~46 caracteres) nas duas colunas.
const _oleo = '''
#Refrão
C                                    Em
Teu óleo santo que marcou a minha fronte
          C7                             F
E o teu sinal que iluminou todo o horizonte
          Fm                                 C
Vêm confirmar-me na missão que é sem fronteira,
            G7                           C
Que o Teu Espírito renove a Terra inteira!

#Primeira Parte
      E7                           Am
Sabedoria, bom conselho, entendimento,
         D7                           G7
Temor, ciência, com piedade, e fortaleza,
         C          A7             Dm   Fm
Eis a bagagem, o roteiro e o bom sustento
              C            D7              G7
De quem se entrega ao novo Reino com firmeza.

#Segunda Parte
            E7                           Am
No mais profundo de mim mesmo e no convívio,
          D7                             G7
Na intimidade ou pelos campos, pelas praças
        C          A7                Dm  Fm
O novo Reino quer ser mais que mero alivio:
            C            D7              G7
É o tal tesouro que não sofre com as traças.

#Terceira Parte
      E7                                  Am
Se homem, mulher qualquer idade, qualquer povo
         D7                            G7
São todos filhos do Pai Nosso Deus de Amor,
         C           A7           Dm  Fm
Nos mais sofridos se revela o reino novo:
         C               D7           G7
Quem os acolhe é que aprendeu a recompor.

#Quarta Parte
       E7                          Am
Onde houver dor ou desalento ou desespero,
        D7                            G7
Eis o terreno para o Reino crescer firme.
        C            A7            Dm  Fm
É desse lado que se espera o nosso esmero
           C           D7             G7
Para que a imagem-semelhança se confirme.

#Quinta Parte
      E7                             Am
A criação tem fonte, rumo e tem destino
         D7                            G7
No Deus amor que tudo deu pra todo mundo.
             C           A7       Dm   Fm
E o que é de todos não merece o desatino
          C               D7             G7
Da exploração e de um descuido tão profundo
''';

Song _song(String title, String txt) => Song(
      id: title,
      title: title,
      key: 'D',
      sections: ChordEngine.importText(txt),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Estaremos Aqui Reunidos', () {
    final song = _song('Estaremos Aqui Reunidos', _estaremos);

    test('vai p/ 2 colunas com fonte bem maior que a de 1 coluna', () {
      final fit = PdfExport.debugFit(song);
      // ignore: avoid_print
      print('estaremos -> col=${fit[0]} fonte=${fit[1].toStringAsFixed(1)} '
          'ocup=${fit[2].toStringAsFixed(2)}');
      expect(fit[0], 2);
      expect(fit[1], greaterThan(11.0), reason: 'saía em 9.5 numa coluna só');
    });

    test('enche a primeira coluna: Segunda Parte fica nela', () {
      final cols = PdfExport.debugColumns(song);
      final esquerda = cols[0].map((r) => r.text).join('\n');
      expect(esquerda, contains('SEGUNDA PARTE'),
          reason: 'sobrava espaço na coluna 1 e ela ia p/ a coluna 2');
      expect(cols[1].map((r) => r.text).join('\n'), contains('TERCEIRA PARTE'));
    });
  });

  group('Maria de Nazaré (sem seção nomeada)', () {
    final song = _song('Maria de Nazaré', _maria);

    test('linha em branco vira separador de grupo', () {
      final blocos = PdfExport.debugBlocks(song);
      expect(blocos.length, greaterThan(1),
          reason: 'sem isso a música inteira é um bloco só e o corte '
              'de coluna cai no meio de uma estrofe');
    });

    test('a coluna 2 começa num começo de grupo, não no meio', () {
      final cols = PdfExport.debugColumns(song);
      if (cols[1].isEmpty) return; // coube em 1 coluna
      final blocos = PdfExport.debugBlocks(song);
      final inicios = blocos.map((b) => b.first.text).toSet();
      expect(inicios, contains(cols[1].first.text));
    });
  });

  group('Teu Óleo Santo (linhas longas)', () {
    final song = _song('Teu Óleo Santo', _oleo);

    test('usa 2 colunas mesmo sem ganhar fonte', () {
      final fit = PdfExport.debugFit(song);
      // Em 1 coluna a fonte seria praticamente a mesma (9.76 contra 9.73),
      // mas o texto ocuparia só ~275pt dos 567 de largura: metade da folha
      // vazia à direita. Dividir usa a página inteira.
      expect(fit[0], 2);
      expect(fit[1], greaterThan(10.5), reason: 'já saiu em 9.57 e em 9.73');
    });

    test('está no teto do que cabe numa página A4', () {
      // Com linhas de ~47 caracteres, duas colunas precisam de 94 caracteres
      // atravessando a folha — é isso que trava a fonte, não a altura. Nenhum
      // corte muda essa conta, então metade da altura sobra mesmo.
      final fit = PdfExport.debugFit(song);
      expect(fit[2], lessThan(0.7), reason: 'sobra altura: quem limita é a largura');
    });

    test('divide 3 seções de cada lado', () {
      final cols = PdfExport.debugColumns(song);
      int secoes(List rows) => rows.where((r) => r.kind == 0).length;
      expect(secoes(cols[0]), 3);
      expect(secoes(cols[1]), 3);
    });
  });

  test('gera o PDF dos dois p/ inspeção', () async {
    final doc = await PdfExport.setlistDoc('Missa Crisma', [
      _song('Estaremos Aqui Reunidos', _estaremos),
      _song('Teu Óleo Santo', _oleo),
      _song('Maria de Nazaré', _maria),
    ]);
    final out = File('build/test-layout.pdf');
    await out.create(recursive: true);
    await out.writeAsBytes(await doc.save());
    expect(doc.document.pdfPageList.pages.length, 4);
  });
}
