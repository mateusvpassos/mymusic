import 'package:flutter_test/flutter_test.dart';
import 'package:mymusic/core/diff.dart';
import 'package:mymusic/models/song.dart';

void main() {
  test('diff por linha', () {
    final d = Diff.linhas('a\nb\nc\nd', 'a\nB\nc\nd\ne');
    expect(d.map((x) => x.toString()).toList(),
        ['  a', '- b', '+ B', '  c', '  d', '+ e']);
  });

  test('resumo esconde o que não mudou', () {
    final d = Diff.linhas('1\n2\n3\n4\n5\n6\n7', '1\n2\n3\nX\n5\n6\n7');
    final r = Diff.resumo(d);
    expect(r.first, isNull); // linhas 1-2 escondidas
    expect(r.whereType<DiffLine>().map((x) => x.text), ['3', '4', 'X', '5']);
    expect(r.last, isNull);
  });

  test('permissão', () {
    const eu = 'ana@x.com';
    bool pode(String dono, {List<String> ed = const [], Map<String, List<String>> conf = const {}}) =>
        Permissao.podeEditar(eu: eu, dono: dono, editores: ed, confianca: conf);
    expect(pode(''), isTrue); // fora do grupo
    expect(pode(eu), isTrue);
    expect(pode('mateus@x.com'), isFalse);
    expect(pode('mateus@x.com', ed: [eu]), isTrue);
    expect(pode('mateus@x.com', conf: {'mateus@x.com': [eu]}), isTrue);
    expect(pode('mateus@x.com', conf: {'bia@x.com': [eu]}), isFalse);
    expect(Permissao.podeEditar(eu: '', dono: '', editores: [], confianca: {}), isFalse);
  });

  test('metadados da nuvem ida e volta; duplicar não herda dono', () {
    final s = Song(id: '1', title: 't', dono: 'm@x.com', donoNome: 'Mateus',
        editores: ['a@x.com'], versao: 3, por: 'a@x.com', porNome: 'Ana');
    final r = Song.fromJson(s.toJson());
    expect([r.dono, r.donoNome, r.editores, r.versao, r.por, r.porNome],
        ['m@x.com', 'Mateus', ['a@x.com'], 3, 'a@x.com', 'Ana']);
    // música só local não ganha campos novos no JSON
    expect(Song(id: '2', title: 'u').toJson().containsKey('dono'), isFalse);
    final sl = Setlist(id: 's', name: 'n', dono: 'm@x.com', editores: ['a@x.com']);
    expect(Setlist.fromJson(sl.toJson()).editores, ['a@x.com']);
  });
}
