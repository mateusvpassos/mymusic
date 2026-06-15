import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import '../data/store.dart';

/// Sync da biblioteca com Google Drive (pasta privada appDataFolder).
class SyncState extends ChangeNotifier {
  static const _fileName = 'mymusic_data.json';

  final GoogleSignIn _gsi = GoogleSignIn(
    scopes: const [drive.DriveApi.driveAppdataScope],
  );

  GoogleSignInAccount? account;
  DateTime? lastSync;
  bool busy = false;
  bool autoSync = true;
  String? error;
  Timer? _autoTimer;

  bool get signedIn => account != null;
  String get email => account?.email ?? '';

  void setAutoSync(bool v) {
    autoSync = v;
    notifyListeners();
  }

  /// Sync automático após salvar (debounce). Não bloqueia UI.
  void scheduleAuto(AppState app) {
    if (!autoSync || !signedIn) return;
    _autoTimer?.cancel();
    _autoTimer = Timer(const Duration(seconds: 4), () => upload(app));
  }

  Future<void> trySilent() async {
    try {
      account = await _gsi.signInSilently();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> signIn() async {
    error = null;
    try {
      account = await _gsi.signIn();
      notifyListeners();
    } catch (e) {
      error = '$e';
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _gsi.signOut();
    account = null;
    notifyListeners();
  }

  Future<drive.DriveApi?> _api() async {
    final client = await _gsi.authenticatedClient();
    if (client == null) return null;
    return drive.DriveApi(client);
  }

  Future<String?> _findId(drive.DriveApi api) async {
    final res = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$_fileName'",
      $fields: 'files(id, name)',
    );
    final files = res.files;
    if (files == null || files.isEmpty) return null;
    return files.first.id;
  }

  /// Envia a biblioteca local para o Drive.
  Future<bool> upload(AppState app) async {
    return _run(() async {
      final api = await _api();
      if (api == null) throw 'Sem autenticação';
      final bytes = utf8.encode(app.exportJson());
      final media = drive.Media(Stream.value(bytes), bytes.length);
      final id = await _findId(api);
      if (id == null) {
        final f = drive.File()
          ..name = _fileName
          ..parents = ['appDataFolder'];
        await api.files.create(f, uploadMedia: media);
      } else {
        await api.files.update(drive.File(), id, uploadMedia: media);
      }
    });
  }

  Future<String?> _downloadRaw() async {
    final api = await _api();
    if (api == null) throw 'Sem autenticação';
    final id = await _findId(api);
    if (id == null) return null;
    final media = await api.files.get(
      id,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final chunks = <int>[];
    await for (final c in media.stream) {
      chunks.addAll(c);
    }
    return utf8.decode(chunks);
  }

  /// Baixa do Drive e SUBSTITUI a biblioteca local.
  Future<bool> download(AppState app) async {
    return _run(() async {
      final raw = await _downloadRaw();
      if (raw == null) throw 'Nenhum backup no Drive';
      app.importJson(raw, replace: true);
    });
  }

  /// Sync bidirecional: baixa e mescla (LWW por updatedAt), depois envia o resultado.
  Future<bool> sync(AppState app) async {
    return _run(() async {
      final raw = await _downloadRaw();
      if (raw != null) app.importJson(raw, replace: false);
      final api = await _api();
      if (api == null) throw 'Sem autenticação';
      final bytes = utf8.encode(app.exportJson());
      final media = drive.Media(Stream.value(bytes), bytes.length);
      final id = await _findId(api);
      if (id == null) {
        final f = drive.File()
          ..name = _fileName
          ..parents = ['appDataFolder'];
        await api.files.create(f, uploadMedia: media);
      } else {
        await api.files.update(drive.File(), id, uploadMedia: media);
      }
    });
  }

  Future<bool> _run(Future<void> Function() body) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await body();
      lastSync = DateTime.now();
      return true;
    } catch (e) {
      error = '$e';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
