import 'dart:math';
import '../models/song.dart';

/// Uma linha já pronta p/ desenhar.
class ChartRow {
  final String text;
  final int kind; // 0 header, 1 chord, 2 lyric, 3 blank
  final bool refrao; // letra do refrão sai em negrito
  const ChartRow(this.text, this.kind, {this.refrao = false});
  double get units => kind == 0 ? 1.7 : (kind == 3 ? 0.8 : 1.0);
}

/// Resultado do cálculo de encaixe de uma música numa página.
class ChartFit {
  final int cols;
  final double font;
  final List<ChartRow> left, right;
  final double leftW, rightW; // cada coluna com a largura do próprio conteúdo
  final bool overflow; // não coube nem espremido -> deixa fluir p/ +1 página
  const ChartFit(this.cols, this.font, this.left, this.right, this.leftW,
      this.rightW, this.overflow);
}

/// Monta a cifra em linhas/blocos e decide colunas e tamanho de fonte.
///
/// Compartilhado entre o PDF e o DOCX p/ os dois saírem iguais.
class ChartLayout {
  // geometria A4 / tipografia (em pontos)
  static const pageW = 595.0, pageH = 842.0;
  static const margin = 12.0; // margens enxutas p/ caber mais na folha
  static const gap = 12.0;
  // Métricas reais da JetBrains Mono (ver test/font_metrics_test.dart):
  // avanço 0.60em, extensão vertical dos glifos 1.153em. Cada linha é
  // desenhada com altura fixa `lineHF`, então a conta de encaixe é exata.
  //
  // `track` aperta as letras 4%: como vale p/ todo caractere (espaço
  // inclusive), o alinhamento acorde/sílaba não muda, e o texto ficando mais
  // estreito sobra largura p/ a fonte crescer — que é o que limita cifra de
  // linha longa em 2 colunas.
  static const track = -0.04;
  static const charWF = 0.60 + track, lineHF = 1.20;
  // base: tamanho alvo. comfort: piso confortável. minFont: abaixo disto
  // desiste de espremer e deixa fluir p/ outra página.
  static const base = 13.0, comfort = 9.5, minFont = 7.5;
  // cabeçalho da música: altura imposta, p/ o espaço restante ser exato
  static const titleH = 34.0;
  // folga contra arredondamento — a Column do pacote pdf descarta tudo se estourar
  static const safety = 0.98;

  static double get usableW => pageW - 2 * margin;
  static double get usableH => (pageH - 2 * margin - titleH) * safety;

  static String chordLine(SongLine l) {
    final sorted = [...l.chords]..sort((a, b) => a.idx.compareTo(b.idx));
    final sb = StringBuffer();
    for (final c in sorted) {
      final at = c.idx < 0 ? 0 : c.idx;
      if (sb.length < at) {
        sb.write(' ' * (at - sb.length));
      } else if (sb.isNotEmpty) {
        sb.write(' ');
      }
      sb.write(c.sym);
    }
    return sb.toString();
  }

  static bool isRefrao(String name) {
    final n = name.toLowerCase();
    return n.contains('refr') || n.contains('chorus') || n.contains('coro');
  }

  /// Grupos que não podem ser partidos entre colunas.
  ///
  /// Quebra em cabeçalho de seção **e em linha em branco**: música sem seção
  /// nomeada costuma marcar os blocos pulando linha, e cortar ali no meio
  /// separa estrofe do próprio refrão.
  static List<List<ChartRow>> blocks(Song song) {
    final out = <List<ChartRow>>[];
    var b = <ChartRow>[];

    // só vira bloco se tiver conteúdo de verdade; separador sozinho é
    // descartado p/ não gerar bloco vazio nem espaço duplicado
    void fecha() {
      if (b.any((r) => r.kind != 3)) out.add(b);
      b = <ChartRow>[];
    }

    for (var s = 0; s < song.sections.length; s++) {
      final sec = song.sections[s];
      final refrao = isRefrao(sec.name);
      fecha();
      if (out.isNotEmpty) b.add(const ChartRow('', 3));
      if (sec.name.isNotEmpty) b.add(ChartRow(sec.name.toUpperCase(), 0));
      for (final l in sec.lines) {
        if (l.chords.isEmpty && l.lyric.trim().isEmpty) {
          fecha();
          b.add(const ChartRow('', 3));
          continue;
        }
        if (l.chords.isNotEmpty) b.add(ChartRow(chordLine(l), 1));
        b.add(ChartRow(l.lyric.isEmpty ? ' ' : l.lyric, 2, refrao: refrao));
      }
    }
    fecha();
    return out;
  }

  static List<ChartRow> rows(Song song) =>
      blocks(song).expand((b) => b).toList();

  static double units(List<ChartRow> rs) =>
      rs.fold<double>(0, (a, r) => a + r.units);

  static int maxLen(List<ChartRow> rs) => rs
      .where((r) => r.kind == 1 || r.kind == 2)
      .fold<int>(1, (m, r) => r.text.length > m ? r.text.length : m);

  /// Divide em 2 colunas cortando só em fronteira de bloco. Se a divisão ficar
  /// muito desequilibrada (um bloco gigante), cai p/ corte por linha.
  static List<List<ChartRow>> split(List<List<ChartRow>> bs) {
    final rs = bs.expand((b) => b).toList();
    final total = units(rs);
    final half = total / 2;

    double acc = 0, bestDiff = double.infinity;
    var bestBlock = -1;
    for (var i = 0; i < bs.length - 1; i++) {
      acc += units(bs[i]);
      final d = (acc - half).abs();
      if (d < bestDiff) {
        bestDiff = d;
        bestBlock = i + 1;
      }
    }
    if (bestBlock > 0 && bestDiff <= total * 0.35) {
      return [
        bs.take(bestBlock).expand((b) => b).toList(),
        bs.skip(bestBlock).expand((b) => b).toList(),
      ];
    }

    acc = 0;
    var s = rs.length;
    for (var i = 0; i < rs.length; i++) {
      acc += rs[i].units;
      if (acc >= half) {
        s = i + 1;
        break;
      }
    }
    return [rs.sublist(0, s), rs.sublist(s)];
  }

  /// Escolhe entre 1 e 2 colunas e a maior fonte que ainda cabe na página.
  ///
  /// As colunas não têm largura fixa: cada uma recebe a largura do seu próprio
  /// conteúdo. Duas colunas estreitas sobram espaço p/ a fonte crescer, o que
  /// não acontecia dividindo a página ao meio.
  static ChartFit fit(Song song, double w, double h) {
    final bs = blocks(song);
    final rs = bs.expand((b) => b).toList();

    // com 2 colunas reserva o vão + os 4pt de respiro de cada coluna
    double fontFor(int lenL, int lenR, double tallest) => [
          base,
          (w - (lenR > 0 ? gap + 4 : 0)) / ((lenL + lenR) * charWF),
          h / (tallest * lineHF),
        ].reduce(min);

    final f1 = fontFor(maxLen(rs), 0, units(rs));
    if (f1 >= base) return ChartFit(1, f1, rs, const [], w, 0, false);

    // candidatos a corte: cada fronteira de bloco + o corte por linha
    // (que cobre a música de bloco único gigante)
    final cortes = <List<List<ChartRow>>>[
      for (var i = 1; i < bs.length; i++)
        [
          bs.take(i).expand((b) => b).toList(),
          bs.skip(i).expand((b) => b).toList(),
        ],
      if (bs.length < 2) split(bs),
    ];

    final cands = <_Cand>[];
    for (final c in cortes) {
      if (c[0].isEmpty || c[1].isEmpty) continue;
      final ll = maxLen(c[0]), lr = maxLen(c[1]);
      final uL = units(c[0]), uR = units(c[1]);
      cands.add(_Cand(c[0], c[1], ll, lr, uL, uR, fontFor(ll, lr, max(uL, uR))));
    }

    if (cands.isNotEmpty) {
      final melhor = cands.map((c) => c.f).reduce(max);
      // A coluna 1 é lida primeiro: ela pode empatar com a 2, mas não ficar
      // bem mais curta. Vale pagar um pouco de fonte por isso, não muito.
      var pool =
          cands.where((c) => c.uL >= c.uR * 0.85 && c.f >= melhor * 0.85).toList();
      if (pool.isEmpty) pool = cands;

      // entre cortes de fonte parecida, o mais equilibrado: 3 seções de cada
      // lado lê melhor do que 5 e 1, e a diferença de fonte é imperceptível
      final topo = pool.map((c) => c.f).reduce(max);
      final esc = (pool.where((c) => c.f >= topo * 0.95).toList()
            ..sort((a, b) => (a.uL - a.uR).abs().compareTo((b.uL - b.uR).abs())))
          .first;

      // Uma coluna só que usa pouco mais da metade da largura desperdiça
      // a folha: nesse caso vale dividir mesmo sem ganhar fonte.
      final estreita = maxLen(rs) * charWF * f1 < w * 0.6;
      final vale = esc.f > f1 * 1.02 || (estreita && esc.f > f1 * 0.95);

      if (esc.f >= minFont && vale) {
        return ChartFit(2, esc.f, esc.l, esc.r, esc.lenL * charWF * esc.f + 4,
            esc.lenR * charWF * esc.f + 4, false);
      }
    }
    if (f1 >= minFont) return ChartFit(1, f1, rs, const [], w, 0, false);

    // não cabe numa página nem espremido: melhor ler em duas páginas
    return ChartFit(1, comfort, rs, const [], w, 0, true);
  }
}

/// Um corte possível em 2 colunas, com o que ele custa em tamanho de fonte.
class _Cand {
  final List<ChartRow> l, r;
  final int lenL, lenR;
  final double uL, uR, f;
  _Cand(this.l, this.r, this.lenL, this.lenR, this.uL, this.uR, this.f);
}
