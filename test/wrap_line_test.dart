import 'package:flutter_test/flutter_test.dart';
import 'package:mymusic/core/chord_engine.dart';
import 'package:mymusic/models/song.dart';
import 'package:mymusic/ui/widgets/chord_chart.dart';

SongLine _l(String chords, String lyric) =>
    ChordEngine.importText('$chords\n$lyric').single.lines.single;

/// Reconstrói "letra" e confere que cada acorde ainda está na mesma sílaba.
Map<String, String> _silabas(List<SongLine> parts) => {
      for (final p in parts)
        for (final c in p.chords)
          '${c.sym}@${p.lyric.trim()}': p.lyric.padRight(c.idx + 3).substring(c.idx, c.idx + 3),
    };

void main() {
  final verso = _l(
    '          Fm                                 C',
    'Vêm confirmar-me na missão que é sem fronteira,',
  );

  test('linha que cabe não mexe', () {
    expect(ChordChart.wrapLine(verso, 80), hasLength(1));
  });

  test('quebra em espaço e nenhum pedaço passa do limite', () {
    final parts = ChordChart.wrapLine(verso, 30);
    expect(parts.length, greaterThan(1));
    for (final p in parts) {
      expect(p.lyric.trimRight().length, lessThanOrEqualTo(30));
      for (final c in p.chords) {
        expect(c.idx + c.sym.length, lessThanOrEqualTo(30));
      }
    }
    // texto inteiro preservado
    expect(parts.map((p) => p.lyric.trim()).join(' '),
        'Vêm confirmar-me na missão que é sem fronteira,');
  });

  test('acorde continua em cima da mesma sílaba depois de quebrar', () {
    // Fm em "irm" de confirmar, C em "fro" de fronteira
    String sil(String lyric, int i) => lyric.padRight(i + 3).substring(i, i + 3);
    final antes = sil(verso.lyric, verso.chords[1].idx);
    final parts = ChordChart.wrapLine(verso, 30);
    final c = parts.expand((p) => p.chords.map((x) => MapEntry(x, p))).firstWhere((e) => e.key.sym == 'C');
    expect(sil(c.value.lyric, c.key.idx), antes);
    expect(antes.trim(), isNotEmpty);
    expect(_silabas(parts).values, contains(antes));
  });

  test('continuação vem recuada', () {
    final parts = ChordChart.wrapLine(verso, 30);
    expect(parts[1].lyric.startsWith('  '), isTrue);
  });

  test('linha só de acordes quebra entre acordes', () {
    final l = _l('C       G       Am      F       C       G       D', '');
    final parts = ChordChart.wrapLine(l, 20);
    expect(parts.expand((p) => p.chords).map((c) => c.sym),
        ['C', 'G', 'Am', 'F', 'C', 'G', 'D']);
    for (final p in parts) {
      for (final c in p.chords) {
        expect(c.idx + c.sym.length, lessThanOrEqualTo(20));
      }
    }
  });

  test('palavra gigante sem espaço não trava', () {
    final l = SongLine('a' * 100, [Chord('C', 0), Chord('G', 60)]);
    final parts = ChordChart.wrapLine(l, 30);
    expect(parts.length, greaterThan(1));
    expect(parts.expand((p) => p.chords).map((c) => c.sym), ['C', 'G']);
  });
}
