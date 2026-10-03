/// Registro do que aconteceu no app — o que mudou, quando, em quê.
class AuditEvent {
  final DateTime at;
  final String
  action; // criou, editou, excluiu, duplicou, importou, sincronizou
  final String entity; // musica, repertorio, config, backup
  final String entityId;
  final String title;
  final List<String> details; // "Tom: C -> D", "Acordes/letra alterados", ...

  AuditEvent({
    required this.at,
    required this.action,
    required this.entity,
    required this.title,
    this.entityId = '',
    this.details = const [],
  });

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'a': action,
    'e': entity,
    'id': entityId,
    't': title,
    if (details.isNotEmpty) 'd': details,
  };

  static AuditEvent fromJson(Map<String, dynamic> j) => AuditEvent(
    at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
    action: j['a'] as String? ?? '?',
    entity: j['e'] as String? ?? '?',
    entityId: j['id'] as String? ?? '',
    title: j['t'] as String? ?? '',
    details: (j['d'] as List? ?? const []).map((e) => e.toString()).toList(),
  );
}

/// Retrato leve de uma música, só p/ saber o que mudou entre duas gravações.
///
/// Guarda um resumo em vez da música inteira: as telas de edição alteram o
/// objeto `Song` no lugar, então comparar com o que está na lista não
/// acusaria diferença nenhuma.
class SongSnap {
  final String title, artist, key, notes;
  final int capo, bpm;
  final String tags;
  final String tempos, momentos;
  final int lines;
  final int contentHash;

  const SongSnap({
    required this.title,
    required this.artist,
    required this.key,
    required this.notes,
    required this.capo,
    required this.bpm,
    required this.tags,
    this.tempos = '',
    this.momentos = '',
    required this.lines,
    required this.contentHash,
  });

  /// Diferenças em português, prontas p/ mostrar na tela.
  List<String> diff(SongSnap o) {
    final d = <String>[];
    void cmp(String label, Object a, Object b) {
      if (a != b) d.add('$label: $a → $b');
    }

    cmp('Título', title, o.title);
    cmp(
      'Artista',
      artist.isEmpty ? '—' : artist,
      o.artist.isEmpty ? '—' : o.artist,
    );
    cmp('Tom', key, o.key);
    cmp('Capo', capo, o.capo);
    cmp('BPM', bpm, o.bpm);
    cmp('Tags', tags.isEmpty ? '—' : tags, o.tags.isEmpty ? '—' : o.tags);
    cmp(
      'Tempos',
      tempos.isEmpty ? '—' : tempos,
      o.tempos.isEmpty ? '—' : o.tempos,
    );
    cmp(
      'Momentos',
      momentos.isEmpty ? '—' : momentos,
      o.momentos.isEmpty ? '—' : o.momentos,
    );
    if (notes != o.notes) d.add('Observações alteradas');
    if (contentHash != o.contentHash) {
      d.add(
        lines == o.lines
            ? 'Cifra alterada'
            : 'Cifra alterada ($lines → ${o.lines} linhas)',
      );
    }
    return d;
  }
}

/// Retrato leve de um repertório.
class SetlistSnap {
  final String name;
  final List<String> songIds;
  final Map<String, int> transpose;
  final Map<String, String> moments;
  final String date;

  const SetlistSnap({
    required this.name,
    required this.songIds,
    required this.transpose,
    this.moments = const {},
    required this.date,
  });

  List<String> diff(SetlistSnap o, String Function(String id) titleOf) {
    final d = <String>[];
    if (name != o.name) d.add('Nome: $name → ${o.name}');
    if (date != o.date)
      d.add(
        'Data: ${date.isEmpty ? '—' : date} → ${o.date.isEmpty ? '—' : o.date}',
      );

    final antes = songIds.toSet(), depois = o.songIds.toSet();
    for (final id in depois.difference(antes)) {
      d.add('Adicionou "${titleOf(id)}"');
    }
    for (final id in antes.difference(depois)) {
      d.add('Removeu "${titleOf(id)}"');
    }
    if (antes.length == depois.length &&
        antes.containsAll(depois) &&
        !_sameOrder(songIds, o.songIds)) {
      d.add('Reordenou as músicas');
    }

    for (final id in depois) {
      final a = transpose[id] ?? 0, b = o.transpose[id] ?? 0;
      if (a != b) {
        d.add('Tom de "${titleOf(id)}": ${_semi(a)} → ${_semi(b)}');
      }
      final ma = moments[id] ?? '—', mb = o.moments[id] ?? '—';
      if (ma != mb) d.add('Momento de "${titleOf(id)}": $ma → $mb');
    }
    return d;
  }

  static String _semi(int v) => v == 0 ? 'original' : (v > 0 ? '+$v' : '$v');

  static bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
