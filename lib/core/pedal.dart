import 'package:flutter/services.dart';
import '../models/song.dart';

/// Mapeamento do pedal (Bluetooth HID = manda teclas).
/// Ações: 'next' (avançar/rolar p/ frente) e 'prev' (voltar).
class Pedal {
  static const actions = ['next', 'prev'];

  static const _defaults = <String, List<int>>{
    'next': [],
    'prev': [],
  };

  // teclas padrão (cobrem a maioria dos page-turners BT)
  static final List<LogicalKeyboardKey> _defNext = [
    LogicalKeyboardKey.pageDown,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.space,
  ];
  static final List<LogicalKeyboardKey> _defPrev = [
    LogicalKeyboardKey.pageUp,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowLeft,
  ];

  static List<int> keysFor(AppSettings s, String action) {
    final custom = s.pedalKeys[action];
    if (custom != null && custom.isNotEmpty) return custom;
    final def = action == 'next' ? _defNext : _defPrev;
    return def.map((k) => k.keyId).toList();
  }

  /// retorna a ação correspondente à tecla, ou null
  static String? actionForKey(AppSettings s, LogicalKeyboardKey key) {
    for (final a in actions) {
      if (keysFor(s, a).contains(key.keyId)) return a;
    }
    return null;
  }

  static String label(int keyId) {
    final k = LogicalKeyboardKey(keyId);
    final dbg = k.debugName;
    return dbg ?? '0x${keyId.toRadixString(16)}';
  }

  static Map<String, List<int>> get defaultsCopy =>
      _defaults.map((k, v) => MapEntry(k, List<int>.of(v)));
}
