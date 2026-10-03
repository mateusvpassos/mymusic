import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../core/chord_engine.dart';
import '../models/audit.dart';
import '../models/song.dart';

/// Estado global + persistência JSON em arquivo único no diretório do app.
class AppState extends ChangeNotifier {
  final List<Song> songs = [];
  final List<Setlist> setlists = [];
  AppSettings settings = AppSettings();

  /// Histórico do que mudou, mais recente primeiro.
  final List<AuditEvent> audit = [];

  /// "Lápides": o que foi excluído e quando (`song:<id>` / `setlist:<id>`).
  /// Viajam no sync do Drive p/ a exclusão chegar nos outros aparelhos — sem
  /// isso o sync baixava a música apagada de volta e ela ressuscitava.
  final Map<String, DateTime> deleted = {};
  static const _tombstoneDays = 365;
  static const _auditMax = 400;

  // retratos da última gravação, p/ saber o que mudou de fato
  final Map<String, SongSnap> _songSnaps = {};
  final Map<String, SetlistSnap> _setSnaps = {};

  File? _file;
  Timer? _debounce;
  bool loaded = false;

  /// Chamado após cada gravação (usado p/ sync automático no Drive).
  void Function()? onPersist;

  /// Mudança feita AQUI (não recebida de outro aparelho) — a sessão ao vivo
  /// usa p/ repassar aos outros. Quem chega via applyRemote* não dispara,
  /// senão a mensagem voltaria em eco.
  void Function(Song s)? onLocalSong;
  void Function(Setlist sl)? onLocalSetlist;

  Future<void> load() async {
    var reparadas = 0;
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/mymusic_data.json');
    if (await _file!.exists()) {
      try {
        final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        songs
          ..clear()
          ..addAll((j['songs'] as List? ?? [])
              .map((e) => Song.fromJson(e as Map<String, dynamic>)));
        // limpeza das linhas em branco acumuladas pelo editor antigo; não mexe
        // no updatedAt (não é edição de verdade, não precisa ganhar no sync)
        for (final s in songs) {
          ChordEngine.trimSectionEnds(s.sections);
          // acorde que versão antiga gravou como letra: aí é conserto de
          // verdade, ganha updatedAt novo p/ chegar nos outros aparelhos
          final n = ChordEngine.repairChordLines(s.sections);
          if (n > 0) {
            s.updatedAt = DateTime.now();
            reparadas++;
            _log('editou', 'musica', s.title, id: s.id, details: [
              'Corrigido automaticamente: $n linha(s) de acorde estavam como letra '
                  '(não apareciam como acorde nem mudavam de tom)',
            ]);
          }
        }
        setlists
          ..clear()
          ..addAll((j['setlists'] as List? ?? [])
              .map((e) => Setlist.fromJson(e as Map<String, dynamic>)));
        if (j['settings'] != null) {
          settings = AppSettings.fromJson(j['settings'] as Map<String, dynamic>);
        }
        audit
          ..clear()
          ..addAll((j['audit'] as List? ?? [])
              .map((e) => AuditEvent.fromJson(e as Map<String, dynamic>)));
        deleted
          ..clear()
          ..addAll(_readTombstones(j['deleted']));
        final limite = DateTime.now().subtract(const Duration(days: _tombstoneDays));
        deleted.removeWhere((_, at) => at.isBefore(limite));
      } catch (_) {/* arquivo corrompido: começa vazio */}
    }
    _resnap();
    loaded = true;
    notifyListeners();
    if (reparadas > 0) _scheduleSave();
  }

  Map<String, dynamic> _toJson() => {
        'songs': songs.map((s) => s.toJson()).toList(),
        'setlists': setlists.map((s) => s.toJson()).toList(),
        'settings': settings.toJson(),
        'audit': audit.map((e) => e.toJson()).toList(),
        'deleted': deleted.map((k, v) => MapEntry(k, v.toIso8601String())),
      };

  static Map<String, DateTime> _readTombstones(dynamic raw) {
    final out = <String, DateTime>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        final at = DateTime.tryParse('$v');
        if (at != null) out['$k'] = at;
      });
    }
    return out;
  }

  /// Excluído depois da última edição desta versão?
  bool _buried(String kind, String id, DateTime updatedAt) {
    final t = deleted['$kind:$id'];
    return t != null && !updatedAt.isAfter(t);
  }

  // ---- auditoria ----

  void _log(String action, String entity, String title,
      {String id = '', List<String> details = const []}) {
    audit.insert(
      0,
      AuditEvent(
        at: DateTime.now(),
        action: action,
        entity: entity,
        entityId: id,
        title: title,
        details: details,
      ),
    );
    if (audit.length > _auditMax) audit.removeRange(_auditMax, audit.length);
  }

  void clearAudit() {
    audit.clear();
    touch();
  }

  static SongSnap _snapOf(Song s) {
    var lines = 0, h = 17;
    for (final sec in s.sections) {
      h = 0x1fffffff & (h * 31 + sec.name.hashCode);
      for (final l in sec.lines) {
        lines++;
        h = 0x1fffffff & (h * 31 + l.lyric.hashCode);
        for (final c in l.chords) {
          h = 0x1fffffff & (h * 31 + c.sym.hashCode * 31 + c.idx);
        }
      }
    }
    return SongSnap(
      title: s.title,
      artist: s.artist,
      key: s.key,
      notes: s.notes,
      capo: s.capo,
      bpm: s.bpm,
      tags: (List.of(s.tags)..sort()).join(', '),
      lines: lines,
      contentHash: h,
    );
  }

  static SetlistSnap _snapOfSet(Setlist sl) => SetlistSnap(
        name: sl.name,
        songIds: List.of(sl.songIds),
        transpose: Map.of(sl.transpose),
        date: sl.date == null ? '' : sl.date!.toIso8601String().substring(0, 10),
      );

  void _resnap() {
    _songSnaps
      ..clear()
      ..addEntries(songs.map((s) => MapEntry(s.id, _snapOf(s))));
    _setSnaps
      ..clear()
      ..addEntries(setlists.map((s) => MapEntry(s.id, _snapOfSet(s))));
  }

  String _titleOf(String id) => songById(id)?.title ?? '(removida)';

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
    final antes = _songSnaps[s.id];
    final agora = _snapOf(s);
    if (i >= 0) {
      songs[i] = s;
      final d = antes?.diff(agora) ?? const <String>[];
      // sem diferença nenhuma é só um salvar repetido: não vira evento
      if (d.isNotEmpty) {
        _log('editou', 'musica', s.title, id: s.id, details: d);
      }
    } else {
      songs.insert(0, s);
      _log('criou', 'musica', s.title, id: s.id);
    }
    _songSnaps[s.id] = agora;
    touch();
    onLocalSong?.call(s);
  }

  void deleteSong(String id) {
    final s = songById(id);
    final usada = setlists.where((sl) => sl.songIds.contains(id)).toList();
    songs.removeWhere((x) => x.id == id);
    deleted['song:$id'] = DateTime.now();
    for (final sl in setlists) {
      if (sl.songIds.remove(id)) _setSnaps[sl.id] = _snapOfSet(sl);
    }
    _songSnaps.remove(id);
    _log('excluiu', 'musica', s?.title ?? id, id: id, details: [
      if (usada.isNotEmpty)
        'Saiu de ${usada.length} repertório(s): ${usada.map((x) => x.name).join(', ')}',
    ]);
    touch();
  }

  Song duplicateSong(Song s) {
    final c = s.copy();
    c.id = ChordEngine.uid();
    c.title = '${s.title} (cópia)';
    c.updatedAt = DateTime.now();
    songs.insert(0, c);
    _songSnaps[c.id] = _snapOf(c);
    _log('duplicou', 'musica', c.title, id: c.id, details: ['Cópia de "${s.title}"']);
    touch();
    onLocalSong?.call(c);
    return c;
  }

  void upsertSetlist(Setlist sl) {
    sl.updatedAt = DateTime.now();
    final i = setlists.indexWhere((x) => x.id == sl.id);
    final antes = _setSnaps[sl.id];
    final agora = _snapOfSet(sl);
    if (i >= 0) {
      setlists[i] = sl;
      final d = antes?.diff(agora, _titleOf) ?? const <String>[];
      if (d.isNotEmpty) {
        _log('editou', 'repertorio', sl.name, id: sl.id, details: d);
      }
    } else {
      setlists.insert(0, sl);
      _log('criou', 'repertorio', sl.name, id: sl.id);
    }
    _setSnaps[sl.id] = agora;
    touch();
    onLocalSetlist?.call(sl);
  }

  Setlist duplicateSetlist(Setlist sl) {
    final c = Setlist(
      id: ChordEngine.uid(),
      name: '${sl.name} (cópia)',
      songIds: List.of(sl.songIds),
      transpose: Map.of(sl.transpose),
    );
    setlists.insert(0, c);
    _setSnaps[c.id] = _snapOfSet(c);
    _log('duplicou', 'repertorio', c.name,
        id: c.id, details: ['Cópia de "${sl.name}"']);
    touch();
    onLocalSetlist?.call(c);
    return c;
  }

  void deleteSetlist(String id) {
    final sl = setlists.where((s) => s.id == id).firstOrNull;
    setlists.removeWhere((s) => s.id == id);
    deleted['setlist:$id'] = DateTime.now();
    _setSnaps.remove(id);
    _log('excluiu', 'repertorio', sl?.name ?? id, id: id, details: [
      if (sl != null) '${sl.songIds.length} música(s) na lista',
    ]);
    touch();
  }

  void updateSettings(void Function(AppSettings) fn) {
    fn(settings);
    touch();
  }

  // ---- vindo de outro aparelho (sessão ao vivo) ----

  /// Aplica música recebida se for mais nova que a daqui (ou não existir).
  /// Devolve a versão local quando a daqui é mais nova, p/ quem mandou
  /// poder se corrigir; null quando aplicou ou é igual.
  Song? applyRemoteSong(Song s, {String de = ''}) {
    final i = songs.indexWhere((x) => x.id == s.id);
    if (i >= 0) {
      final local = songs[i];
      if (local.updatedAt.isAfter(s.updatedAt)) return local;
      if (!s.updatedAt.isAfter(local.updatedAt)) return null; // igual
    }
    final antes = _songSnaps[s.id];
    final agora = _snapOf(s);
    if (i >= 0) {
      songs[i] = s;
    } else {
      songs.insert(0, s);
    }
    _songSnaps[s.id] = agora;
    final d = antes?.diff(agora) ?? const <String>[];
    if (antes == null || d.isNotEmpty) {
      _log(antes == null ? 'recebeu' : 'editou', 'musica', s.title,
          id: s.id, details: [if (de.isNotEmpty) 'Pela sessão ao vivo ($de)', ...d]);
    }
    touch();
    return null;
  }

  Setlist? applyRemoteSetlist(Setlist sl, {String de = ''}) {
    final i = setlists.indexWhere((x) => x.id == sl.id);
    if (i >= 0) {
      final local = setlists[i];
      if (local.updatedAt.isAfter(sl.updatedAt)) return local;
      if (!sl.updatedAt.isAfter(local.updatedAt)) return null;
    }
    final antes = _setSnaps[sl.id];
    final agora = _snapOfSet(sl);
    if (i >= 0) {
      setlists[i] = sl;
    } else {
      setlists.insert(0, sl);
    }
    _setSnaps[sl.id] = agora;
    final d = antes?.diff(agora, _titleOf) ?? const <String>[];
    if (antes == null || d.isNotEmpty) {
      _log(antes == null ? 'recebeu' : 'editou', 'repertorio', sl.name,
          id: sl.id, details: [if (de.isNotEmpty) 'Pela sessão ao vivo ($de)', ...d]);
    }
    touch();
    return null;
  }

  Setlist? setlistById(String id) {
    for (final s in setlists) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Registra algo que não passa pelas mutações (sync, exportação...).
  void logEvent(String action, String entity, String title,
          {List<String> details = const []}) =>
      _log(action, entity, title, details: details);

  // ---- backup ----
  String exportJson() => const JsonEncoder.withIndent('  ').convert(_toJson());

  /// Importa backup.
  /// replace=true substitui tudo; senão faz merge LWW (mantém o mais recente por updatedAt).
  /// Retorna nº de músicas importadas.
  int importJson(String text, {bool replace = false, String origem = 'arquivo'}) {
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
      deleted.clear();
    }
    // junta as lápides (vale a exclusão mais recente)
    _readTombstones(j['deleted']).forEach((k, at) {
      final cur = deleted[k];
      if (cur == null || at.isAfter(cur)) deleted[k] = at;
    });
    final antesS = songs.length, antesL = setlists.length;
    for (final s in inSongs) {
      if (_buried('song', s.id, s.updatedAt)) continue; // excluída depois
      final i = songs.indexWhere((x) => x.id == s.id);
      if (i < 0) {
        songs.add(s);
      } else if (replace || s.updatedAt.isAfter(songs[i].updatedAt)) {
        songs[i] = s;
      }
    }
    for (final sl in inSets) {
      if (_buried('setlist', sl.id, sl.updatedAt)) continue;
      final i = setlists.indexWhere((x) => x.id == sl.id);
      if (i < 0) {
        setlists.add(sl);
      } else if (replace || sl.updatedAt.isAfter(setlists[i].updatedAt)) {
        setlists[i] = sl;
      }
    }
    // o que outro aparelho excluiu sai daqui também
    var removidasS = 0, removidosL = 0;
    songs.removeWhere((x) {
      final r = _buried('song', x.id, x.updatedAt);
      if (r) removidasS++;
      return r;
    });
    setlists.removeWhere((x) {
      final r = _buried('setlist', x.id, x.updatedAt);
      if (r) removidosL++;
      return r;
    });
    if (j['settings'] != null && replace) {
      settings = AppSettings.fromJson(j['settings'] as Map<String, dynamic>);
    }
    _resnap();
    final doDrive = origem == 'drive';
    _log(doDrive ? 'sincronizou' : 'importou', 'backup',
        doDrive
            ? (replace ? 'Baixou do Drive (substituiu)' : 'Sync com o Drive')
            : (replace ? 'Importou backup (substituiu)' : 'Importou backup (mesclou)'),
        details: [
          '${inSongs.length} música(s) recebida(s)',
          '${inSets.length} repertório(s) recebido(s)',
          if (removidasS + removidosL > 0)
            'Excluídos em outro aparelho: $removidasS música(s), $removidosL repertório(s)',
          'Total agora: ${songs.length} música(s), ${setlists.length} repertório(s)'
              '${replace ? '' : ' (antes: $antesS e $antesL)'}',
        ]);
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
