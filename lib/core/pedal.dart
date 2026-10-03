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

  // nomes das teclas que pedal de virar página costuma mandar
  static final Map<int, String> _nomes = {
    LogicalKeyboardKey.pageDown.keyId: 'Page Down',
    LogicalKeyboardKey.pageUp.keyId: 'Page Up',
    LogicalKeyboardKey.arrowDown.keyId: 'Seta ↓',
    LogicalKeyboardKey.arrowUp.keyId: 'Seta ↑',
    LogicalKeyboardKey.arrowRight.keyId: 'Seta →',
    LogicalKeyboardKey.arrowLeft.keyId: 'Seta ←',
    LogicalKeyboardKey.space.keyId: 'Espaço',
    LogicalKeyboardKey.enter.keyId: 'Enter',
    LogicalKeyboardKey.backspace.keyId: 'Apagar',
    LogicalKeyboardKey.audioVolumeUp.keyId: 'Volume +',
    LogicalKeyboardKey.audioVolumeDown.keyId: 'Volume −',
    LogicalKeyboardKey.mediaPlayPause.keyId: 'Play/Pause',
    LogicalKeyboardKey.mediaTrackNext.keyId: 'Próxima faixa',
    LogicalKeyboardKey.mediaTrackPrevious.keyId: 'Faixa anterior',
  };

  /// Nome legível da tecla. `debugName` só existe em build de debug — na
  /// versão instalada vinha null e a tela mostrava "0x100000307".
  static String label(int keyId) {
    final n = _nomes[keyId];
    if (n != null) return n;
    final l = LogicalKeyboardKey(keyId).keyLabel.trim();
    if (l.isNotEmpty) return l.length == 1 ? l.toUpperCase() : l;
    return 'Tecla ${keyId.toRadixString(16)}';
  }

  static Map<String, List<int>> get defaultsCopy =>
      _defaults.map((k, v) => MapEntry(k, List<int>.of(v)));
}
