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

  Map<String, dynamic> toJson() => {
    'l': lyric,
    'c': chords.map((c) => c.toJson()).toList(),
  };
  factory SongLine.fromJson(Map<String, dynamic> j) => SongLine(
    j['l'] as String,
    (j['c'] as List)
        .map((e) => Chord.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
  SongLine copy() => SongLine(lyric, chords.map((c) => c.copy()).toList());
}

class Section {
  String name;
  List<SongLine> lines;
  Section(this.name, this.lines);

  Map<String, dynamic> toJson() => {
    'n': name,
    'l': lines.map((l) => l.toJson()).toList(),
  };
  factory Section.fromJson(Map<String, dynamic> j) => Section(
    j['n'] as String,
    (j['l'] as List)
        .map((e) => SongLine.fromJson(e as Map<String, dynamic>))
        .toList(),
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
  int bpm; // 0 = sem BPM
  // velocidade da auto-rolagem desta música (px/s); 0 = a das configurações
  double scrollSpeed;
  // tempos litúrgicos em que cabe (vazio = qualquer) e momentos da Missa
  List<String> tempos;
  List<String> momentos;
  // nuvem (grupo compartilhado): quem criou, quem mais pode editar, nº da
  // versão e quem fez a última mudança. Vazio = só neste aparelho.
  String dono;
  String donoNome;
  List<String> editores;
  int versao;
  String por;
  String porNome;
  // acervo geral: a mesma música (obra) pode ter várias versões/arranjos
  // ("Original", "Simplificada", "Versão rcc"). [obra] vazio = é a própria.
  String obra;
  String nomeVersao;
  // de qual versão do acervo esta veio (e em que revisão), p/ avisar quando
  // a do acervo mudar
  String baseId;
  int baseRev;
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
    this.bpm = 0,
    this.scrollSpeed = 0,
    List<String>? tempos,
    List<String>? momentos,
    this.dono = '',
    this.donoNome = '',
    List<String>? editores,
    this.versao = 0,
    this.por = '',
    this.porNome = '',
    this.obra = '',
    this.nomeVersao = '',
    this.baseId = '',
    this.baseRev = 0,
    DateTime? updatedAt,
  }) : sections = sections ?? [],
       editores = editores ?? [],
       tags = tags ?? [],
       tempos = tempos ?? [],
       momentos = momentos ?? [],
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
    'bpm': bpm,
    if (scrollSpeed > 0) 'scrollSpeed': scrollSpeed,
    if (tempos.isNotEmpty) 'tempos': tempos,
    if (momentos.isNotEmpty) 'momentos': momentos,
    ..._metaJson(dono, donoNome, editores, por, porNome),
    if (versao > 0) 'versao': versao,
    if (obra.isNotEmpty) 'obra': obra,
    if (nomeVersao.isNotEmpty) 'nomeVersao': nomeVersao,
    if (baseId.isNotEmpty) 'baseId': baseId,
    if (baseRev > 0) 'baseRev': baseRev,
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
    bpm: (j['bpm'] ?? 0) as int,
    scrollSpeed: ((j['scrollSpeed'] ?? 0) as num).toDouble(),
    tempos: (j['tempos'] as List? ?? []).map((e) => e as String).toList(),
    momentos: (j['momentos'] as List? ?? []).map((e) => e as String).toList(),
    dono: (j['dono'] ?? '') as String,
    donoNome: (j['donoNome'] ?? '') as String,
    editores: _strList(j['editores']),
    versao: ((j['versao'] ?? 0) as num).toInt(),
    por: (j['por'] ?? '') as String,
    porNome: (j['porNome'] ?? '') as String,
    obra: (j['obra'] ?? '') as String,
    nomeVersao: (j['nomeVersao'] ?? '') as String,
    baseId: (j['baseId'] ?? '') as String,
    baseRev: ((j['baseRev'] ?? 0) as num).toInt(),
    updatedAt:
        DateTime.tryParse((j['updatedAt'] ?? '') as String) ?? DateTime.now(),
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
    bpm: bpm,
    scrollSpeed: scrollSpeed,
    tempos: List.of(tempos),
    momentos: List.of(momentos),
    dono: dono,
    donoNome: donoNome,
    editores: List.of(editores),
    versao: versao,
    por: por,
    porNome: porNome,
    obra: obra,
    nomeVersao: nomeVersao,
    baseId: baseId,
    baseRev: baseRev,
    updatedAt: updatedAt,
  );
}

List<String> _strList(dynamic v) =>
    (v as List? ?? const []).map((e) => e as String).toList();

Map<String, dynamic> _metaJson(
  String dono,
  String donoNome,
  List<String> editores,
  String por,
  String porNome,
) => {
  if (dono.isNotEmpty) 'dono': dono,
  if (donoNome.isNotEmpty) 'donoNome': donoNome,
  if (editores.isNotEmpty) 'editores': editores,
  if (por.isNotEmpty) 'por': por,
  if (porNome.isNotEmpty) 'porNome': porNome,
};

class Setlist {
  String id;
  String name;
  List<String> songIds;
  Map<String, int> transpose; // songId -> semitons (tom salvo no repertório)
  Map<String, String> moments; // songId -> momento da Missa ("Entrada"...)
  // nuvem: igual à música
  String dono;
  String donoNome;
  List<String> editores;
  String por;
  String porNome;
  DateTime? date; // data do evento (opcional)
  DateTime updatedAt;

  Setlist({
    required this.id,
    required this.name,
    List<String>? songIds,
    Map<String, int>? transpose,
    Map<String, String>? moments,
    this.dono = '',
    this.donoNome = '',
    List<String>? editores,
    this.por = '',
    this.porNome = '',
    this.date,
    DateTime? updatedAt,
  }) : songIds = songIds ?? [],
       transpose = transpose ?? {},
       moments = moments ?? {},
       editores = editores ?? [],
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'songIds': songIds,
    'transpose': transpose,
    if (moments.isNotEmpty) 'moments': moments,
    ..._metaJson(dono, donoNome, editores, por, porNome),
    'date': date?.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Setlist.fromJson(Map<String, dynamic> j) => Setlist(
    id: j['id'] as String,
    name: j['name'] as String,
    songIds: (j['songIds'] as List? ?? []).map((e) => e as String).toList(),
    transpose: (j['transpose'] as Map? ?? {}).map(
      (k, v) => MapEntry(k as String, (v as num).toInt()),
    ),
    moments: (j['moments'] as Map? ?? {}).map(
      (k, v) => MapEntry(k as String, v as String),
    ),
    dono: (j['dono'] ?? '') as String,
    donoNome: (j['donoNome'] ?? '') as String,
    editores: _strList(j['editores']),
    por: (j['por'] ?? '') as String,
    porNome: (j['porNome'] ?? '') as String,
    date: (j['date'] != null && (j['date'] as String).isNotEmpty)
        ? DateTime.tryParse(j['date'] as String)
        : null,
    updatedAt:
        DateTime.tryParse((j['updatedAt'] ?? '') as String) ?? DateTime.now(),
  );
}

class AppSettings {
  int seedColor; // ARGB
  bool dark;
  double fontScale; // 0.8 .. 2.0
  double scrollSpeed; // px/s no auto-scroll
  // quanto um toque no pedal rola, em fração da altura da tela (0.1 .. 1.0)
  double pageStep;
  // nome deste aparelho na sessão ao vivo
  String deviceName;
  // tela da música só com a letra, grande (p/ quem canta)
  bool lyricsOnly;
  // Mapeamento do pedal: ação -> lista de teclas (logicalKeyId)
  Map<String, List<int>> pedalKeys;

  AppSettings({
    this.seedColor = 0xFF3D5AFE,
    this.dark = true,
    this.fontScale = 1.0,
    this.scrollSpeed = 28,
    this.pageStep = 0.4,
    this.deviceName = '',
    this.lyricsOnly = false,
    Map<String, List<int>>? pedalKeys,
  }) : pedalKeys = pedalKeys ?? {};

  Map<String, dynamic> toJson() => {
    'seedColor': seedColor,
    'dark': dark,
    'fontScale': fontScale,
    'scrollSpeed': scrollSpeed,
    'pageStep': pageStep,
    if (deviceName.isNotEmpty) 'deviceName': deviceName,
    if (lyricsOnly) 'lyricsOnly': true,
    'pedalKeys': pedalKeys.map((k, v) => MapEntry(k, v)),
  };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
    seedColor: (j['seedColor'] ?? 0xFF3D5AFE) as int,
    dark: (j['dark'] ?? true) as bool,
    fontScale: ((j['fontScale'] ?? 1.0) as num).toDouble(),
    scrollSpeed: ((j['scrollSpeed'] ?? 28) as num).toDouble(),
    pageStep: ((j['pageStep'] ?? 0.4) as num).toDouble().clamp(0.1, 1.0),
    deviceName: (j['deviceName'] ?? '') as String,
    lyricsOnly: (j['lyricsOnly'] ?? false) as bool,
    pedalKeys: (j['pedalKeys'] as Map? ?? {}).map(
      (k, v) =>
          MapEntry(k as String, (v as List).map((e) => e as int).toList()),
    ),
  );
}
