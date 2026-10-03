import '../models/song.dart';
import 'chord_engine.dart';

/// Uma linha da comparação entre duas versões.
class DiffLine {
  final String text;
  final int tipo; // 0 = igual, 1 = entrou, -1 = saiu
  const DiffLine(this.text, this.tipo);
  @override
  String toString() => '${tipo > 0 ? '+' : tipo < 0 ? '-' : ' '} $text';
}

class Diff {
  /// Diferença por linha (maior subsequência comum). Cifras têm poucas
  /// centenas de linhas: o O(n·m) é instantâneo.
  static List<DiffLine> linhas(String antes, String depois) {
    final a = antes.split('\n'), b = depois.split('\n');
    final n = a.length, m = b.length;
    final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        lcs[i][j] = a[i] == b[j]
            ? lcs[i + 1][j + 1] + 1
            : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
      }
    }
    final out = <DiffLine>[];
    var i = 0, j = 0;
    while (i < n && j < m) {
      if (a[i] == b[j]) {
        out.add(DiffLine(a[i], 0));
        i++;
        j++;
      } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
        out.add(DiffLine(a[i++], -1));
      } else {
        out.add(DiffLine(b[j++], 1));
      }
    }
    while (i < n) {
      out.add(DiffLine(a[i++], -1));
    }
    while (j < m) {
      out.add(DiffLine(b[j++], 1));
    }
    return out;
  }

  /// Texto da música como no editor ([G]letra, #Seção) — é o que se compara.
  static String texto(Song s) => ChordEngine.serializeSections(s.sections);

  /// Só os trechos que mudaram, com [contexto] linhas iguais em volta
  /// (null no lugar das iguais escondidas).
  static List<DiffLine?> resumo(List<DiffLine> d, {int contexto = 1}) {
    final mostra = List<bool>.filled(d.length, false);
    for (var k = 0; k < d.length; k++) {
      if (d[k].tipo == 0) continue;
      for (var c = k - contexto; c <= k + contexto; c++) {
        if (c >= 0 && c < d.length) mostra[c] = true;
      }
    }
    final out = <DiffLine?>[];
    var pulou = false;
    for (var k = 0; k < d.length; k++) {
      if (mostra[k]) {
        if (pulou) out.add(null);
        out.add(d[k]);
        pulou = false;
      } else {
        pulou = true;
      }
    }
    if (pulou && out.isNotEmpty) out.add(null);
    return out;
  }
}

/// Quem pode mexer no quê (as mesmas regras do servidor, em
/// firebase/firestore.rules — aqui só p/ a tela já mostrar certo).
class Permissao {
  /// [confianca]: dono -> e-mails que ele liberou p/ tudo dele.
  static bool podeEditar({
    required String eu,
    required String dono,
    required List<String> editores,
    required Map<String, List<String>> confianca,
  }) {
    if (eu.isEmpty) return false;
    if (dono.isEmpty || dono == eu) return true; // ainda não é do grupo / é meu
    return editores.contains(eu) || (confianca[dono]?.contains(eu) ?? false);
  }
}
