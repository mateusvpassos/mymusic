import '../models/song.dart';

/// Calendário litúrgico (rito romano, como celebrado no Brasil) e momentos
/// da Missa — p/ sugerir cantos e organizar o repertório.
class Liturgia {
  static const tempos = [
    'Advento',
    'Natal',
    'Quaresma',
    'Semana Santa',
    'Páscoa',
    'Pentecostes',
    'Tempo Comum',
  ];

  /// Na ordem em que acontecem na Missa.
  static const momentos = [
    'Entrada',
    'Ato Penitencial',
    'Glória',
    'Salmo',
    'Aclamação',
    'Ofertório',
    'Santo',
    'Cordeiro',
    'Comunhão',
    'Ação de Graças',
    'Final',
  ];

  static DateTime _dia(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  /// Domingo de Páscoa (algoritmo de Meeus/Jones/Butcher).
  static DateTime pascoa(int ano) {
    final a = ano % 19, b = ano ~/ 100, c = ano % 100;
    final d = b ~/ 4, e = b % 4, f = (b + 8) ~/ 25, g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4, k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final mes = (h + l - 7 * m + 114) ~/ 31;
    final dia = (h + l - 7 * m + 114) % 31 + 1;
    return DateTime.utc(ano, mes, dia);
  }

  /// 1º domingo do Advento: 4 domingos antes do Natal.
  static DateTime advento(int ano) {
    final vespera = DateTime.utc(ano, 12, 24);
    final quartoDomingo = vespera.subtract(Duration(days: vespera.weekday % 7));
    return quartoDomingo.subtract(const Duration(days: 21));
  }

  /// Batismo do Senhor (fim do tempo do Natal). No Brasil a Epifania é no
  /// domingo entre 2 e 8 de janeiro; caindo dia 7 ou 8, o Batismo é na
  /// segunda seguinte.
  static DateTime batismo(int ano) {
    var epifania = DateTime.utc(ano, 1, 2);
    while (epifania.weekday != DateTime.sunday) {
      epifania = epifania.add(const Duration(days: 1));
    }
    return epifania.add(Duration(days: epifania.day >= 7 ? 1 : 7));
  }

  /// Tempos que valem na data, o mais específico primeiro
  /// (ex.: domingo de Pentecostes -> [Pentecostes, Páscoa]).
  static List<String> temposDe(DateTime data) {
    final d = _dia(data);
    final p = pascoa(d.year);
    int diff(DateTime x) => d.difference(x).inDays;
    if (!d.isBefore(advento(d.year)) &&
        d.isBefore(DateTime.utc(d.year, 12, 25))) {
      return const ['Advento'];
    }
    if (d.month == 12 && d.day >= 25) return const ['Natal'];
    if (!d.isAfter(batismo(d.year))) return const ['Natal'];
    final dp = diff(p);
    if (dp >= -46 && dp <= -8) return const ['Quaresma'];
    if (dp >= -7 && dp <= -1) return const ['Semana Santa', 'Quaresma'];
    if (dp >= 48 && dp <= 49) return const ['Pentecostes', 'Páscoa'];
    if (dp >= 0 && dp <= 49) return const ['Páscoa'];
    return const ['Tempo Comum'];
  }

  /// Ordem do momento na Missa (sem momento vai p/ o fim).
  static int ordem(String? momento) {
    final i = momento == null ? -1 : momentos.indexOf(momento);
    return i < 0 ? momentos.length : i;
  }
}

/// Quando a música foi tocada: tirado dos repertórios com data.
class SongUse {
  final DateTime ultima;
  final int vezes;
  const SongUse(this.ultima, this.vezes);
}

class UsoMusicas {
  /// Uso de cada música nos repertórios com data até [ate] (inclusive; por
  /// padrão hoje). [exceto] = repertório a ignorar (o que está sendo montado).
  static Map<String, SongUse> calcula(
    Iterable<Setlist> setlists, {
    DateTime? ate,
    String? exceto,
  }) {
    final limite = Liturgia._dia(ate ?? DateTime.now());
    final ultima = <String, DateTime>{};
    final vezes = <String, int>{};
    for (final sl in setlists) {
      if (sl.date == null || sl.id == exceto) continue;
      final d = Liturgia._dia(sl.date!);
      if (d.isAfter(limite)) continue;
      for (final id in sl.songIds.toSet()) {
        vezes[id] = (vezes[id] ?? 0) + 1;
        final u = ultima[id];
        if (u == null || d.isAfter(u)) ultima[id] = d;
      }
    }
    return {
      for (final e in ultima.entries) e.key: SongUse(e.value, vezes[e.key]!),
    };
  }

  /// "hoje", "há 3 semanas", "12/03/2025"...
  static String quando(DateTime d, {DateTime? hoje}) {
    final h = Liturgia._dia(hoje ?? DateTime.now());
    final dias = h.difference(Liturgia._dia(d)).inDays;
    if (dias <= 0) return 'hoje';
    if (dias == 1) return 'ontem';
    if (dias < 7) return 'há $dias dias';
    if (dias < 60) {
      final s = dias ~/ 7;
      return s == 1 ? 'há 1 semana' : 'há $s semanas';
    }
    if (dias < 365) return 'há ${dias ~/ 30} meses';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}
