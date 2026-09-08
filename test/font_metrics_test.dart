// Mede as métricas reais da JetBrains Mono usadas no cálculo de encaixe do PDF.
// Se a fonte for trocada e os números mudarem, este teste avisa.
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:pdf/src/pdf/font/ttf_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
