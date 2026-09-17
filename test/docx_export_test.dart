import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:mymusic/core/chord_engine.dart';
import 'package:mymusic/core/docx_export.dart';
import 'package:mymusic/models/song.dart';

const _cifra = '''
#Refrão
       C       G     C
Estaremos aqui reunidos
        F       D     G
Como estavam em Jerusalém

#Primeira Parte
        G                   C
Ninguém para esse vento passando
        Dm        G       C    G7
Faz a igreja de Cristo crescer
''';

Song _song() => Song(
      id: 'x',
      title: 'Estaremos Aqui Reunidos',
      artist: 'Padre Zezinho',
      key: 'C',
      sections: ChordEngine.importText(_cifra),
    );

Map<String, String> _unzip(List<int> bytes) {
  final ar = ZipDecoder().decodeBytes(bytes);
  return {
    for (final f in ar.files)
      if (f.isFile) f.name: utf8.decode(f.content as List<int>)
  };
}

void main() {
  final bytes = DocxExport.buildDocx(
      DocxExport.songBody(_song(), chordColor: Colors.blue));
  final partes = _unzip(bytes);

  test('tem as partes obrigatórias de um .docx', () {
    expect(partes.keys, containsAll(<String>[
      '[Content_Types].xml',
      '_rels/.rels',
      'word/document.xml',
    ]));
  });

  test('acento sobrevive (UTF-8, não UTF-16)', () {
    final doc = partes['word/document.xml']!;
    expect(doc, contains('Jerusalém'));
    expect(doc, contains('Refrão'.toUpperCase()));
    expect(doc, contains('Ninguém'));
  });

  test('espaço do alinhamento é preservado', () {
    // sem xml:space="preserve" o Word come os espaços e o acorde
    // desencosta da sílaba
    final doc = partes['word/document.xml']!;
    expect(doc, contains('xml:space="preserve"'));
    expect(doc, contains('>       C       G     C<'));
  });

  test('mesmo aperto entre letras do PDF', () {
    expect(partes['word/document.xml']!, contains('<w:spacing w:val="-'));
  });

  test('XML bem formado: tags abrem e fecham na ordem', () {
    final doc = partes['word/document.xml']!;
    final pilha = <String>[];
    final re = RegExp(r'<(/?)([A-Za-z0-9:_.-]+)([^>]*?)(/?)>');
    for (final m in re.allMatches(doc)) {
      if (m.group(2)!.startsWith('?')) continue;
      final fecha = m.group(1) == '/';
      final selfClose = m.group(4) == '/';
      if (selfClose) continue;
      if (fecha) {
        expect(pilha.isNotEmpty, isTrue, reason: 'fecha ${m.group(2)} sem abrir');
        expect(pilha.removeLast(), m.group(2));
      } else {
        pilha.add(m.group(2)!);
      }
    }
    expect(pilha, isEmpty, reason: 'tags abertas sem fechar: $pilha');
  });

  test('salva o arquivo p/ inspeção', () async {
    final f = File('build/test-cifra.docx');
    await f.create(recursive: true);
    await f.writeAsBytes(bytes);
    expect(await f.length(), greaterThan(500));
  });

  group('música longa (2 colunas)', () {
    // repete as seções até o layout precisar dividir
    final longa = Song(
      id: 'y',
      title: 'Longa',
      key: 'C',
      sections: ChordEngine.importText(
          List.filled(5, _cifra).join('\n').replaceAllMapped(
              RegExp(r'#(Refrão|Primeira Parte)'),
              (m) => '#${m[1]} ${DateTime.now().microsecond}')),
    );
    final b2 = DocxExport.buildDocx(
        DocxExport.songBody(longa, chordColor: Colors.blue));
    final p2 = _unzip(b2);

    test('vira tabela de 2 colunas', () {
      expect(p2['word/document.xml']!, contains('<w:tbl>'));
      expect(p2['word/document.xml']!, contains('<w:gridCol'));
    });

    test('toda célula termina com um parágrafo (exigência do Word)', () {
      final doc = p2['word/document.xml']!;
      for (final m in RegExp(r'<w:tc>.*?</w:tc>', dotAll: true).allMatches(doc)) {
        expect(m.group(0)!, endsWith('</w:p></w:tc>'),
            reason: 'célula sem parágrafo final faz o Word recusar o arquivo');
      }
    });

    test('salva o de 2 colunas p/ inspeção', () async {
      final f = File('build/test-cifra-2col.docx');
      await f.create(recursive: true);
      await f.writeAsBytes(b2);
      expect(await f.length(), greaterThan(500));
    });
  });
}
