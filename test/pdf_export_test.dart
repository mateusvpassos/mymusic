import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymusic/core/chord_engine.dart';
import 'package:mymusic/core/pdf_export.dart';
import 'package:mymusic/models/song.dart';

const _cifra = '''
#Intro
C  G7  C

#Primeira Parte
     C       G7    C    C7
Estaremos aqui reunidos
        F          D  G7
Como estavam em Jerusalém
          Dm     G7     C  G/B  Am
Pois só quando vivemos uni_______dos
           F      G7        C
É que o Espírito Santo nos vem

#Refrão
         G7                 C
Ninguém para esse vento passando
         E       E7         Am
Ninguém vê e ele sopra onde quer
         F           Fm      C    Am
Força igual tem o Espírito quando
         Dm      G7        C
Faz a igreja de Cristo crescer

#Segunda Parte
          G7                   C
Feita de homens, a igreja é divina
          E     E7        Am
Pois o Espírito Santo a conduz
         F          Fm        C   Am
Como um fogo que aquece e ilumina
         Dm         G7          C
Que é pureza, que é vida, que é luz

#Terceira Parte
      G7                  C
Sua imagem são línguas ardentes
         E      E7   Am
Pois o amor é comunicação
        F        Fm       C     Am
E é preciso que todas as gentes
         Dm     G7      C
Saibam quanto felizes serão
''';

Song _song(String title, String txt) => Song(
      id: title,
      title: title,
      artist: 'Padre Zezinho',
      key: 'C',
      sections: ChordEngine.importText(txt),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('gera PDF de repertório p/ inspeção visual', () async {
    // versão longa: 5 partes + refrão repetido (força 2 colunas)
    final longa = StringBuffer(_cifra);
    for (final p in ['Quarta Parte', 'Quinta Parte', 'Sexta Parte']) {
      longa.writeln('\n#$p');
      longa.writeln(_cifra.split('#Refrão\n').last.split('#Segunda')[0].trim());
      longa.writeln('\n#Refrão');
      longa.writeln(_cifra.split('#Refrão\n')[1].split('#Segunda')[0].trim());
    }

    final songs = [
      _song('Estaremos Aqui Reunidos', _cifra),
      _song('Cantar a Beleza da Vida', longa.toString()),
      _song('Curta', '#Intro\nC G\n#Refrão\n C   G\nSó um trecho'),
    ];
    final doc = await PdfExport.setlistDoc('Missa de domingo', songs);
    final bytes = await doc.save();
    final out = File('build/test-setlist.pdf');
    await out.create(recursive: true);
    await out.writeAsBytes(bytes);

    expect(bytes.length, greaterThan(1000));
    // capa + 1 página por música (nenhuma deve estourar p/ página extra)
    expect(doc.document.pdfPageList.pages.length, 4);
  });

  test('linha em branco entre seções tem altura real', () {
    final rows = PdfExport.debugRows(_song('x', _cifra));
    final blanks = rows.where((r) => r.kind == 3).length;
    expect(blanks, 4, reason: '5 seções -> 4 separadores');
    for (final r in rows.where((r) => r.kind == 3)) {
      expect(r.units, greaterThan(0));
    }
  });

  test('corte de 2 colunas cai em fronteira de seção', () {
    final song = _song('x', _cifra);
    final parts = PdfExport.debugSplit(song);
    // primeira linha da 2ª coluna deve ser separador ou cabeçalho de seção
    expect(parts[1].first.kind, anyOf(0, 3));
  });
}
