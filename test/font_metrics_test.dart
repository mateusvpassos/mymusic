// Mede as métricas reais da JetBrains Mono usadas no cálculo de encaixe do PDF.
// Se a fonte for trocada e os números mudarem, este teste avisa.
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:pdf/src/pdf/font/ttf_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('negrito tem a mesma largura da regular', () async {
    double widthOf(TtfParser p) {
      final gi = p.charToGlyphIndexMap['M'.codeUnitAt(0)]!;
      return p.glyphInfoMap[gi]!.advanceWidth;
    }

    final reg = TtfParser(await rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf'));
    final bold = TtfParser(await rootBundle.load('assets/fonts/JetBrainsMono-Bold.ttf'));
    // o refrão sai em negrito e os acordes também — se a largura diferisse,
    // o acorde não ficaria mais em cima da sílaba certa
    expect(widthOf(bold), closeTo(widthOf(reg), 0.001));
  });

  test('métricas da JetBrains Mono', () async {
    final p = TtfParser(await rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf'));

    double? advance;
    var top = 0.0, bottom = 0.0;
    const sample = 'ABCDEFGabcdefgpqyj0123456789#ÁÉÍÓÚÃÕÇáéíóúãõç/()_-';
    for (final c in sample.codeUnits) {
      final gi = p.charToGlyphIndexMap[c];
      if (gi == null) continue;
      final m = p.glyphInfoMap[gi]!;
      advance ??= m.advanceWidth;
      expect(m.advanceWidth, closeTo(advance!, 0.001), reason: 'não é monoespaçada');
      if (m.top < top) top = m.top;
      if (m.bottom > bottom) bottom = m.bottom;
    }

    // ignore: avoid_print
    print('advanceWidth=$advance  bboxTop=$top  bboxBottom=$bottom  '
        'extent=${bottom - top}  emptyLineHeight=${p.ascent - p.descent}');

    expect(advance, closeTo(0.6, 0.005));
  });
}
