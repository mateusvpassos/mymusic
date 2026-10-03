import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymusic/core/pedal.dart';

void main() {
  test('teclas do pedal com nome legível (não hex)', () {
    expect(Pedal.label(LogicalKeyboardKey.pageDown.keyId), 'Page Down');
    expect(Pedal.label(LogicalKeyboardKey.space.keyId), 'Espaço');
    expect(Pedal.label(LogicalKeyboardKey.arrowDown.keyId), 'Seta ↓');
    expect(Pedal.label(LogicalKeyboardKey.keyB.keyId), 'B');
    for (final k in [LogicalKeyboardKey.pageUp, LogicalKeyboardKey.f5, LogicalKeyboardKey.keyN]) {
      expect(Pedal.label(k.keyId), isNot(startsWith('0x')));
    }
  });
}
