// Modelo de dados puro (sem widgets) — serializável em JSON.

class Chord {
  String sym;
  int idx; // posição do caractere na lyric
  Chord(this.sym, this.idx);

  Map<String, dynamic> toJson() => {'s': sym, 'i': idx};
  factory Chord.fromJson(Map<String, dynamic> j) =>
      Chord(j['s'] as String, j['i'] as int);
  Chord copy() => Chord(sym, idx);
}

class SongLine {
  String lyric;
  List<Chord> chords;
  SongLine(this.lyric, this.chords);

  Map<String, dynamic> toJson() =>
      {'l': lyric, 'c': chords.map((c) => c.toJson()).toList()};
  factory SongLine.fromJson(Map<String, dynamic> j) => SongLine(
        j['l'] as String,
        (j['c'] as List).map((e) => Chord.fromJson(e as Map<String, dynamic>)).toList(),
      );
  SongLine copy() => SongLine(lyric, chords.map((c) => c.copy()).toList());
}

class Section {
  String name;
  List<SongLine> lines;
  Section(this.name, this.lines);

  Map<String, dynamic> toJson() =>
      {'n': name, 'l': lines.map((l) => l.toJson()).toList()};
  factory Section.fromJson(Map<String, dynamic> j) => Section(
        j['n'] as String,
        (j['l'] as List).map((e) => SongLine.fromJson(e as Map<String, dynamic>)).toList(),
      );
  Section copy() => Section(name, lines.map((l) => l.copy()).toList());
}

class Song {
  String id;
  String title;
  String artist;
  String key; // tom (ex.: "G", "Em")
  int capo;
  List<Section> sections;
  List<String> tags;
  String notes; // anotações pessoais (ex.: "entra suave", "repete 2x")
  DateTime updatedAt;

  Song({
    required this.id,
    required this.title,
    this.artist = '',
    this.key = 'C',
    this.capo = 0,
    List<Section>? sections,
    List<String>? tags,
    this.notes = '',
    DateTime? updatedAt,
  })  : sections = sections ?? [],
        tags = tags ?? [],
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'key': key,
        'capo': capo,
        'sections': sections.map((s) => s.toJson()).toList(),
        'tags': tags,
        'notes': notes,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Song.fromJson(Map<String, dynamic> j) => Song(
        id: j['id'] as String,
        title: j['title'] as String,
        artist: (j['artist'] ?? '') as String,
        key: (j['key'] ?? 'C') as String,
        capo: (j['capo'] ?? 0) as int,
        sections: (j['sections'] as List? ?? [])
            .map((e) => Section.fromJson(e as Map<String, dynamic>))
            .toList(),
        tags: (j['tags'] as List? ?? []).map((e) => e as String).toList(),
        notes: (j['notes'] ?? '') as String,
        updatedAt: DateTime.tryParse((j['updatedAt'] ?? '') as String) ?? DateTime.now(),
      );

  Song copy() => Song(
        id: id,
        title: title,
        artist: artist,
        key: key,
        capo: capo,
        sections: sections.map((s) => s.copy()).toList(),
        tags: List.of(tags),
        notes: notes,
        updatedAt: updatedAt,
      );
}

class Setlist {
  String id;
  String name;
  List<String> songIds;
  Map<String, int> transpose; // songId -> semitons (tom salvo no repertório)
  DateTime? date; // data do evento (opcional)
  DateTime updatedAt;

  Setlist({
    required this.id,
    required this.name,
    List<String>? songIds,
    Map<String, int>? transpose,
    this.date,
    DateTime? updatedAt,
  })  : songIds = songIds ?? [],
        transpose = transpose ?? {},
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'songIds': songIds,
        'transpose': transpose,
        'date': date?.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Setlist.fromJson(Map<String, dynamic> j) => Setlist(
        id: j['id'] as String,
        name: j['name'] as String,
        songIds: (j['songIds'] as List? ?? []).map((e) => e as String).toList(),
        transpose: (j['transpose'] as Map? ?? {})
            .map((k, v) => MapEntry(k as String, (v as num).toInt())),
        date: (j['date'] != null && (j['date'] as String).isNotEmpty)
            ? DateTime.tryParse(j['date'] as String)
            : null,
        updatedAt: DateTime.tryParse((j['updatedAt'] ?? '') as String) ?? DateTime.now(),
      );
}

class AppSettings {
  int seedColor; // ARGB
  bool dark;
  double fontScale; // 0.8 .. 2.0
  double scrollSpeed; // px/s no auto-scroll
  // Mapeamento do pedal: ação -> lista de teclas (logicalKeyId)
  Map<String, List<int>> pedalKeys;

  AppSettings({
    this.seedColor = 0xFF3D5AFE,
    this.dark = true,
    this.fontScale = 1.0,
    this.scrollSpeed = 28,
    Map<String, List<int>>? pedalKeys,
  }) : pedalKeys = pedalKeys ?? {};

  Map<String, dynamic> toJson() => {
        'seedColor': seedColor,
        'dark': dark,
        'fontScale': fontScale,
        'scrollSpeed': scrollSpeed,
        'pedalKeys': pedalKeys.map((k, v) => MapEntry(k, v)),
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        seedColor: (j['seedColor'] ?? 0xFF3D5AFE) as int,
        dark: (j['dark'] ?? true) as bool,
        fontScale: ((j['fontScale'] ?? 1.0) as num).toDouble(),
        scrollSpeed: ((j['scrollSpeed'] ?? 28) as num).toDouble(),
        pedalKeys: (j['pedalKeys'] as Map? ?? {}).map(
          (k, v) => MapEntry(k as String, (v as List).map((e) => e as int).toList()),
        ),
      );
}
