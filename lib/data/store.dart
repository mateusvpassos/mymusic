import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../core/chord_engine.dart';
import '../models/song.dart';

/// Estado global + persistência JSON em arquivo único no diretório do app.
class AppState extends ChangeNotifier {
  final List<Song> songs = [];
  final List<Setlist> setlists = [];
  AppSettings settings = AppSettings();

  File? _file;
  Timer? _debounce;
  bool loaded = false;

  /// Chamado após cada gravação (usado p/ sync automático no Drive).
  void Function()? onPersist;

  Future<void> load() async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/mymusic_data.json');
    if (await _file!.exists()) {
      try {
        final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        songs
          ..clear()
          ..addAll((j['songs'] as List? ?? [])
              .map((e) => Song.fromJson(e as Map<String, dynamic>)));
        setlists
          ..clear()
          ..addAll((j['setlists'] as List? ?? [])
              .map((e) => Setlist.fromJson(e as Map<String, dynamic>)));
        if (j['settings'] != null) {
          settings = AppSettings.fromJson(j['settings'] as Map<String, dynamic>);
        }
      } catch (_) {/* arquivo corrompido: começa vazio */}
    }
    loaded = true;
    notifyListeners();
  }

  Map<String, dynamic> _toJson() => {
        'songs': songs.map((s) => s.toJson()).toList(),
        'setlists': setlists.map((s) => s.toJson()).toList(),
        'settings': settings.toJson(),
      };

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _saveNow);
  }

  Future<void> _saveNow() async {
    if (_file == null) return;
    await _file!.writeAsString(jsonEncode(_toJson()));
  }

  // ---- mutações ----
  void touch() {
    notifyListeners();
    _scheduleSave();
    onPersist?.call();
  }

  Song? songById(String id) {
    for (final s in songs) {
      if (s.id == id) return s;
    }
    return null;
  }

  void upsertSong(Song s) {
    s.updatedAt = DateTime.now();
    final i = songs.indexWhere((x) => x.id == s.id);
    if (i >= 0) {
      songs[i] = s;
    } else {
      songs.insert(0, s);
    }
    touch();
  }

  void deleteSong(String id) {
    songs.removeWhere((s) => s.id == id);
    for (final sl in setlists) {
      sl.songIds.remove(id);
    }
    touch();
  }

  Song duplicateSong(Song s) {
    final c = s.copy();
    c.id = ChordEngine.uid();
    c.title = '${s.title} (cópia)';
    c.updatedAt = DateTime.now();
    songs.insert(0, c);
    touch();
    return c;
  }

  void upsertSetlist(Setlist sl) {
    sl.updatedAt = DateTime.now();
    final i = setlists.indexWhere((x) => x.id == sl.id);
    if (i >= 0) {
      setlists[i] = sl;
    } else {
      setlists.insert(0, sl);
    }
    touch();
  }

  Setlist duplicateSetlist(Setlist sl) {
    final c = Setlist(
      id: ChordEngine.uid(),
      name: '${sl.name} (cópia)',
      songIds: List.of(sl.songIds),
      transpose: Map.of(sl.transpose),
    );
    setlists.insert(0, c);
    touch();
    return c;
  }

  void deleteSetlist(String id) {
    setlists.removeWhere((s) => s.id == id);
    touch();
  }

  void updateSettings(void Function(AppSettings) fn) {
    fn(settings);
    touch();
  }

  // ---- backup ----
  String exportJson() => const JsonEncoder.withIndent('  ').convert(_toJson());

  /// Importa backup.
  /// replace=true substitui tudo; senão faz merge LWW (mantém o mais recente por updatedAt).
  /// Retorna nº de músicas importadas.
  int importJson(String text, {bool replace = false}) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    final inSongs = (j['songs'] as List? ?? [])
        .map((e) => Song.fromJson(e as Map<String, dynamic>))
        .toList();
    final inSets = (j['setlists'] as List? ?? [])
        .map((e) => Setlist.fromJson(e as Map<String, dynamic>))
        .toList();
    if (replace) {
      songs.clear();
      setlists.clear();
    }
    for (final s in inSongs) {
      final i = songs.indexWhere((x) => x.id == s.id);
      if (i < 0) {
        songs.add(s);
      } else if (replace || s.updatedAt.isAfter(songs[i].updatedAt)) {
        songs[i] = s;
      }
    }
    for (final sl in inSets) {
      final i = setlists.indexWhere((x) => x.id == sl.id);
      if (i < 0) {
        setlists.add(sl);
      } else if (replace || sl.updatedAt.isAfter(setlists[i].updatedAt)) {
        setlists[i] = sl;
      }
    }
    if (j['settings'] != null && replace) {
      settings = AppSettings.fromJson(j['settings'] as Map<String, dynamic>);
    }
    touch();
    return inSongs.length;
  }

  Future<String> writeBackupFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/mymusic_backup.json');
    await f.writeAsString(exportJson());
    return f.path;
  }

}
