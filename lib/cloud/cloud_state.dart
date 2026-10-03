import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';
import '../core/diff.dart';
import '../data/store.dart';
import '../models/song.dart';
import 'cloud_config.dart';

/// Grupo compartilhado na nuvem.
class Grupo {
  final String id, nome, dono;
  final List<String> membros;
  const Grupo(this.id, this.nome, this.dono, this.membros);

  factory Grupo.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final j = d.data() ?? const {};
    return Grupo(
      d.id,
      (j['nome'] ?? '') as String,
      (j['dono'] ?? '') as String,
      ((j['membros'] as List?) ?? const []).cast<String>(),
    );
  }
}

/// Mudança proposta por quem não pode editar a música.
class Sugestao {
  final String id, songId, titulo, por, porNome, status, dono;
  final String decididoPor, decididoPorNome, motivo, nota;
  final int base; // versão da música quando foi sugerida
  final Song song;
  final DateTime? em, decididoEm;

  const Sugestao({
    required this.id,
    required this.songId,
    required this.titulo,
    required this.por,
    required this.porNome,
    required this.status,
    required this.dono,
    required this.decididoPor,
    required this.decididoPorNome,
    required this.motivo,
    required this.nota,
    required this.base,
    required this.song,
    this.em,
    this.decididoEm,
  });

  bool get pendente => status == 'pendente';

  factory Sugestao.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final j = d.data() ?? const {};
    return Sugestao(
      id: d.id,
      songId: (j['songId'] ?? '') as String,
      titulo: (j['titulo'] ?? '') as String,
      por: (j['por'] ?? '') as String,
      porNome: (j['porNome'] ?? '') as String,
      status: (j['status'] ?? 'pendente') as String,
      dono: (j['dono'] ?? '') as String,
      decididoPor: (j['decididoPor'] ?? '') as String,
      decididoPorNome: (j['decididoPorNome'] ?? '') as String,
      motivo: (j['motivo'] ?? '') as String,
      nota: (j['nota'] ?? '') as String,
      base: ((j['base'] ?? 0) as num).toInt(),
      song: Song.fromJson(_norm(j['song'] ?? {'id': '', 'title': ''})),
      em: _data(j['em']),
      decididoEm: _data(j['decididoEm']),
    );
  }
}

/// Retrato de uma gravação da música (histórico).
class Versao {
  final String id, por, porNome, acao;
  final int n;
  final Song song;
  final DateTime? em;
  final List<String> resumo;
  const Versao(
    this.id,
    this.n,
    this.song,
    this.por,
    this.porNome,
    this.acao,
    this.em,
    this.resumo,
  );

  factory Versao.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final j = d.data() ?? const {};
    return Versao(
      d.id,
      ((j['n'] ?? 0) as num).toInt(),
      Song.fromJson(_norm(j['song'])),
      (j['por'] ?? '') as String,
      (j['porNome'] ?? '') as String,
      (j['acao'] ?? '') as String,
      _data(j['em']),
      ((j['resumo'] as List?) ?? const []).cast<String>(),
    );
  }
}

/// Mapa do Firestore -> JSON puro (mapas aninhados vêm com tipos genéricos
/// que os fromJson do modelo não aceitam).
Map<String, dynamic> _norm(dynamic m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

DateTime? _data(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// Liga a biblioteca local (AppState) ao grupo no Firestore.
///
/// A tela continua lendo o AppState; aqui só se leva o que muda daqui p/ a
/// nuvem (com versão e autor) e o que chega de lá p/ cá. Quem não pode
/// editar uma música manda sugestão — as regras do servidor
/// (firebase/firestore.rules) garantem isso mesmo se o app errar.
class CloudState extends ChangeNotifier {
  final AppState app;
  CloudState(this.app);

  bool get disponivel => CloudConfig.ligado;
  User? user;
  String get eu => (user?.email ?? '').toLowerCase();
  String get nome {
    final n = user?.displayName ?? '';
    return n.isNotEmpty ? n : eu.split('@').first;
  }

  List<Grupo> grupos = [];
  Grupo? grupo;
  bool get ativa => user != null && grupo != null;

  /// Já entrou num grupo antes neste aparelho (vai religar ao abrir).
  bool get vaiUsarGrupo => disponivel && _grupoSalvo.isNotEmpty;
  bool get souDonoDoGrupo => grupo != null && grupo!.dono == eu;

  /// dono -> e-mails que podem editar tudo dele
  final Map<String, List<String>> confianca = {};

  /// e-mail -> nome
  final Map<String, String> nomes = {};

  List<Sugestao> sugestoes = [];
  String? erro;
  bool ocupado = false;
  bool carregou = false; // primeira leitura das músicas do grupo chegou

  final Set<String> _songsNaNuvem = {}, _setsNaNuvem = {};
  final Map<String, Song> _ultimaDaNuvem = {};
  final List<StreamSubscription> _subs = [];
  StreamSubscription? _authSub, _gruposSub;
  final Map<String, Song> _pendSongs = {};
  final Map<String, Setlist> _pendSets = {};
  Timer? _flushTimer;
  String _grupoSalvo = '';

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  DocumentReference<Map<String, dynamic>> get _g =>
      _db.collection('grupos').doc(grupo!.id);

  String nomeDe(String email) {
    if (email.isEmpty) return '';
    if (email == eu) return nome;
    return nomes[email] ?? email.split('@').first;
  }

  // ---------------- início ----------------

  Future<void> init() async {
    app.localSongHooks.add(_onLocalSong);
    app.localSetlistHooks.add(_onLocalSetlist);
    app.localDeleteHooks.add(_onLocalDelete);
    if (!disponivel) return;
    _grupoSalvo = await _lePrefs();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((u) {
      user = u;
      _ouvirGrupos();
      notifyListeners();
    });
  }

  Future<File> _prefsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/cloud_prefs.json');
  }

  Future<String> _lePrefs() async {
    try {
      final f = await _prefsFile();
      if (await f.exists()) {
        return ((jsonDecode(await f.readAsString()) as Map)['grupoId'] ?? '')
            as String;
      }
    } catch (_) {}
    return '';
  }

  Future<void> _gravaPrefs() async {
    try {
      await (await _prefsFile()).writeAsString(
        jsonEncode({'grupoId': grupo?.id ?? ''}),
      );
    } catch (_) {}
  }

  // ---------------- login ----------------

  Future<void> entrar() async {
    erro = null;
    try {
      final gsi = GoogleSignIn(
        scopes: const ['email'],
        serverClientId: CloudConfig.webClientId,
      );
      final acc = await gsi.signIn();
      if (acc == null) return;
      final a = await acc.authentication;
      await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(
          idToken: a.idToken,
          accessToken: a.accessToken,
        ),
      );
    } catch (e) {
      erro = 'Não foi possível entrar: $e';
      notifyListeners();
    }
  }

  /// Só no emulador do Firebase: entra com qualquer e-mail (sem Google).
  Future<void> entrarTeste(String email, String nomeTeste) async {
    final cred = GoogleAuthProvider.credential(
      idToken: jsonEncode({
        'sub': email.toLowerCase(),
        'email': email.toLowerCase(),
        'email_verified': true,
        'name': nomeTeste,
      }),
    );
    final r = await FirebaseAuth.instance.signInWithCredential(cred);
    if ((r.user?.displayName ?? '').isEmpty) {
      await r.user?.updateDisplayName(nomeTeste);
      await r.user?.reload();
      user = FirebaseAuth.instance.currentUser;
    }
  }

  Future<void> sair() async {
    await _flush();
    _pararGrupo();
    // saiu: no próximo início volta a sincronizar pelo Drive
    _grupoSalvo = '';
    await _gravaPrefs();
    await FirebaseAuth.instance.signOut();
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    grupos = [];
    notifyListeners();
  }

  // ---------------- grupos ----------------

  void _ouvirGrupos() {
    _gruposSub?.cancel();
    _gruposSub = null;
    if (user == null) {
      _pararGrupo();
      return;
    }
    _gruposSub = _db
        .collection('grupos')
        .where('membros', arrayContains: eu)
        .snapshots()
        .listen(
          (q) {
            grupos = q.docs.map(Grupo.fromDoc).toList()
              ..sort((a, b) => a.nome.compareTo(b.nome));
            final atual = grupo == null
                ? null
                : grupos.where((x) => x.id == grupo!.id).firstOrNull;
            if (grupo != null && atual == null) {
              // tiraram este aparelho do grupo
              _pararGrupo();
            } else if (atual != null) {
              grupo = atual;
            } else {
              final salvo = grupos
                  .where((x) => x.id == _grupoSalvo)
                  .firstOrNull;
              final escolhido =
                  salvo ?? (grupos.length == 1 ? grupos.first : null);
              if (escolhido != null) _abrirGrupo(escolhido);
            }
            notifyListeners();
          },
          onError: (e) {
            erro = '$e';
            notifyListeners();
          },
        );
  }

  Future<void> criarGrupo(String nomeGrupo) async {
    final ref = _db.collection('grupos').doc();
    await _semEsperar(
      ref.set({
        'nome': nomeGrupo,
        'dono': eu,
        'membros': [eu],
        'criadoEm': FieldValue.serverTimestamp(),
      }),
    );
    _abrirGrupo(Grupo(ref.id, nomeGrupo, eu, [eu]));
    notifyListeners();
  }

  void escolherGrupo(Grupo g) {
    if (grupo?.id == g.id) return;
    _pararGrupo();
    _abrirGrupo(g);
    notifyListeners();
  }

  Future<void> convidar(String email) async {
    final e = email.trim().toLowerCase();
    if (grupo == null || e.isEmpty || grupo!.membros.contains(e)) return;
    await _semEsperar(
      _g.update({
        'membros': FieldValue.arrayUnion([e]),
      }),
    );
  }

  Future<void> remover(String email) async {
    if (grupo == null || email == grupo!.dono) return;
    await _semEsperar(
      _g.update({
        'membros': FieldValue.arrayRemove([email]),
      }),
    );
  }

  /// Quem pode editar TODAS as minhas músicas e repertórios sem pedir.
  Future<void> setConfianca(List<String> emails) async {
    if (!ativa) return;
    await _semEsperar(
      _g.collection('confianca').doc(eu).set({'editores': emails}),
    );
  }

  void _abrirGrupo(Grupo g) {
    grupo = g;
    carregou = false;
    app.cloudAtiva = true;
    _gravaPrefs();
    _subs.add(
      _g.collection('musicas').snapshots().listen(_onMusicas, onError: _onErro),
    );
    _subs.add(
      _g
          .collection('repertorios')
          .snapshots()
          .listen(_onRepertorios, onError: _onErro),
    );
    _subs.add(
      _g.collection('confianca').snapshots().listen((q) {
        confianca
          ..clear()
          ..addEntries(
            q.docs.map(
              (d) => MapEntry(
                d.id,
                ((d.data()['editores'] as List?) ?? const []).cast<String>(),
              ),
            ),
          );
        notifyListeners();
      }, onError: _onErro),
    );
    _subs.add(
      _g.collection('pessoas').snapshots().listen((q) {
        nomes
          ..clear()
          ..addEntries(
            q.docs.map(
              (d) => MapEntry(d.id, (d.data()['nome'] ?? '') as String),
            ),
          );
        notifyListeners();
      }, onError: _onErro),
    );
    // pendentes (p/ quem decide) + as minhas, de qualquer situação
    final pend = <String, Sugestao>{}, minhas = <String, Sugestao>{};
    void junta() {
      sugestoes = {...minhas, ...pend}.values.toList()
        ..sort((a, b) => (b.em ?? DateTime(0)).compareTo(a.em ?? DateTime(0)));
      notifyListeners();
    }

    _subs.add(
      _g
          .collection('sugestoes')
          .where('status', isEqualTo: 'pendente')
          .snapshots()
          .listen((q) {
            pend
              ..clear()
              ..addEntries(
                q.docs.map((d) => MapEntry(d.id, Sugestao.fromDoc(d))),
              );
            junta();
          }, onError: _onErro),
    );
    _subs.add(
      _g.collection('sugestoes').where('por', isEqualTo: eu).snapshots().listen(
        (q) {
          minhas
            ..clear()
            ..addEntries(
              q.docs.map((d) => MapEntry(d.id, Sugestao.fromDoc(d))),
            );
          junta();
        },
        onError: _onErro,
      ),
    );
    // meu nome p/ os outros verem
    _semEsperar(
      _g.collection('pessoas').doc(eu).set({
        'nome': nome,
        'visto': FieldValue.serverTimestamp(),
      }),
    );
  }

  void _pararGrupo() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    grupo = null;
    app.cloudAtiva = false;
    _songsNaNuvem.clear();
    _setsNaNuvem.clear();
    _ultimaDaNuvem.clear();
    sugestoes = [];
    confianca.clear();
    carregou = false;
  }

  void _onErro(Object e) {
    erro = '$e';
    notifyListeners();
  }

  // ---------------- permissões ----------------

  bool podeEditarSong(Song s) =>
      !ativa ||
      Permissao.podeEditar(
        eu: eu,
        dono: s.dono,
        editores: s.editores,
        confianca: confianca,
      );

  bool podeEditarSetlist(Setlist sl) =>
      !ativa ||
      Permissao.podeEditar(
        eu: eu,
        dono: sl.dono,
        editores: sl.editores,
        confianca: confianca,
      );

  bool souDono(String dono) => !ativa || dono.isEmpty || dono == eu;

  /// Só o dono escolhe quem mais pode editar esta música/repertório.
  Future<void> setEditoresSong(Song s, List<String> emails) async {
    if (!souDono(s.dono)) return;
    s.editores = List.of(emails);
    app.touch();
    await _semEsperar(
      _g.collection('musicas').doc(s.id).update({'editores': emails}),
    );
  }

  Future<void> setEditoresSetlist(Setlist sl, List<String> emails) async {
    if (!souDono(sl.dono)) return;
    sl.editores = List.of(emails);
    app.touch();
    await _semEsperar(
      _g.collection('repertorios').doc(sl.id).update({'editores': emails}),
    );
  }

  // ---------------- daqui p/ a nuvem ----------------

  /// Músicas/repertórios deste aparelho que ainda não estão no grupo.
  int get songsSoAqui =>
      app.songs.where((s) => !_songsNaNuvem.contains(s.id)).length;
  int get setsSoAqui =>
      app.setlists.where((s) => !_setsNaNuvem.contains(s.id)).length;

  /// Manda p/ o grupo o que só existe aqui (quem manda vira o dono).
  Future<void> enviarBiblioteca() async {
    if (!ativa) return;
    for (final s in app.songs) {
      if (!_songsNaNuvem.contains(s.id)) _pendSongs[s.id] = s;
    }
    for (final sl in app.setlists) {
      if (!_setsNaNuvem.contains(sl.id)) _pendSets[sl.id] = sl;
    }
    await _flush();
  }

  void _onLocalSong(Song s) {
    if (!ativa || !podeEditarSong(s)) return;
    _pendSongs[s.id] = s;
    _agendar();
  }

  void _onLocalSetlist(Setlist sl) {
    if (!ativa || !podeEditarSetlist(sl)) return;
    _pendSets[sl.id] = sl;
    _agendar();
  }

  // junta toques seguidos (capo +, +, +) numa versão só
  void _agendar() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 1500), _flush);
  }

  Future<void> _flush() async {
    _flushTimer?.cancel();
    if (!ativa) return;
    final songs = _pendSongs.values.toList();
    final sets = _pendSets.values.toList();
    _pendSongs.clear();
    _pendSets.clear();
    for (final s in songs) {
      _gravarSong(s, acao: _songsNaNuvem.contains(s.id) ? 'editou' : 'criou');
    }
    for (final sl in sets) {
      final novo = !_setsNaNuvem.contains(sl.id);
      if (novo && sl.dono.isEmpty) {
        sl
          ..dono = eu
          ..donoNome = nome;
      }
      sl
        ..por = eu
        ..porNome = nome;
      _setsNaNuvem.add(sl.id);
      _semEsperar(
        _g.collection('repertorios').doc(sl.id).set({
          ...sl.toJson(),
          'apagada': false,
        }),
      );
    }
    if (songs.isNotEmpty || sets.isNotEmpty) app.touch();
  }

  /// Grava a música e um retrato dela no histórico, no mesmo lote.
  void _gravarSong(Song s, {required String acao}) {
    final novo = !_songsNaNuvem.contains(s.id);
    if (novo && s.dono.isEmpty) {
      s
        ..dono = eu
        ..donoNome = nome;
    }
    final antes = _ultimaDaNuvem[s.id];
    s
      ..versao = (antes?.versao ?? s.versao) + 1
      ..por = eu
      ..porNome = nome;
    final resumo = antes == null
        ? const <String>[]
        : AppState.resumoMudancas(antes, s);
    final ref = _g.collection('musicas').doc(s.id);
    final b = _db.batch()
      ..set(ref, {...s.toJson(), 'apagada': false})
      ..set(ref.collection('versoes').doc(), {
        'n': s.versao,
        'song': s.toJson(),
        'por': eu,
        'porNome': nome,
        'em': FieldValue.serverTimestamp(),
        'acao': acao,
        'resumo': resumo,
      });
    _songsNaNuvem.add(s.id);
    _ultimaDaNuvem[s.id] = s.copy();
    _semEsperar(b.commit());
  }

  void _onLocalDelete(String kind, String id) {
    if (!ativa) return;
    final col = kind == 'song' ? 'musicas' : 'repertorios';
    final naNuvem = kind == 'song'
        ? _songsNaNuvem.contains(id)
        : _setsNaNuvem.contains(id);
    if (!naNuvem) return;
    _semEsperar(
      _g.collection(col).doc(id).update({
        'apagada': true,
        'apagadaPor': eu,
        'apagadaPorNome': nome,
        'updatedAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  /// Não espera o servidor (offline a escrita fica na fila do Firestore);
  /// erro de permissão aparece na tela e a versão da nuvem volta.
  Future<void> _semEsperar(Future<void> f) async {
    unawaited(
      f.catchError((Object e) {
        erro = e is FirebaseException && e.code == 'permission-denied'
            ? 'Sem permissão para essa mudança — ela foi desfeita.'
            : '$e';
        notifyListeners();
      }),
    );
  }

  // ---------------- da nuvem p/ cá ----------------

  void _onMusicas(QuerySnapshot<Map<String, dynamic>> q) {
    for (final ch in q.docChanges) {
      final d = ch.doc;
      final j = d.data();
      if (j == null) continue;
      _songsNaNuvem.add(d.id);
      if (d.metadata.hasPendingWrites)
        continue; // eco do que este aparelho mandou
      if (j['apagada'] == true) {
        _ultimaDaNuvem.remove(d.id);
        app.removeByCloud(
          'song',
          d.id,
          por: (j['apagadaPorNome'] ?? j['apagadaPor'] ?? '') as String,
        );
        continue;
      }
      final s = Song.fromJson(_norm(j));
      _ultimaDaNuvem[d.id] = s.copy();
      app.applyCloudSong(s, forcar: !podeEditarSong(s));
    }
    if (!carregou) {
      carregou = true;
      notifyListeners();
    }
  }

  void _onRepertorios(QuerySnapshot<Map<String, dynamic>> q) {
    for (final ch in q.docChanges) {
      final d = ch.doc;
      final j = d.data();
      if (j == null) continue;
      _setsNaNuvem.add(d.id);
      if (d.metadata.hasPendingWrites) continue;
      if (j['apagada'] == true) {
        app.removeByCloud(
          'setlist',
          d.id,
          por: (j['apagadaPorNome'] ?? j['apagadaPor'] ?? '') as String,
        );
        continue;
      }
      final sl = Setlist.fromJson(_norm(j));
      app.applyCloudSetlist(sl, forcar: !podeEditarSetlist(sl));
    }
    notifyListeners();
  }

  // ---------------- sugestões ----------------

  /// Pendentes que ESTE usuário pode aceitar/recusar.
  List<Sugestao> get paraDecidir => sugestoes.where((x) {
    if (!x.pendente || x.por == eu) return false;
    final s = app.songById(x.songId);
    return s != null && podeEditarSong(s);
  }).toList();

  List<Sugestao> get minhas => sugestoes.where((x) => x.por == eu).toList();

  Future<void> sugerir(Song proposta, {String nota = ''}) async {
    if (!ativa) return;
    final atual = app.songById(proposta.id);
    await _semEsperar(
      _g.collection('sugestoes').doc().set({
        'songId': proposta.id,
        'titulo': proposta.title,
        'song': proposta.toJson(),
        'base': atual?.versao ?? 0,
        'dono': atual?.dono ?? '',
        'por': eu,
        'porNome': nome,
        'nota': nota,
        'em': FieldValue.serverTimestamp(),
        'status': 'pendente',
      }),
    );
  }

  /// Aceita: a música passa a ser a sugerida (mantendo dono e editores).
  Future<void> aceitar(Sugestao x) async {
    final atual = app.songById(x.songId);
    if (atual == null || !podeEditarSong(atual)) return;
    final nova = x.song.copy()
      ..dono = atual.dono
      ..donoNome = atual.donoNome
      ..editores = List.of(atual.editores)
      ..versao = atual.versao
      ..updatedAt = DateTime.now();
    app.applyCloudSong(nova, forcar: true);
    _gravarSong(
      nova,
      acao: 'aceitou sugestão de ${x.porNome.isNotEmpty ? x.porNome : x.por}',
    );
    app.touch();
    await _decidir(x, 'aceita');
  }

  Future<void> recusar(Sugestao x, {String motivo = ''}) =>
      _decidir(x, 'recusada', motivo: motivo);

  Future<void> _decidir(Sugestao x, String status, {String motivo = ''}) =>
      _semEsperar(
        _g.collection('sugestoes').doc(x.id).update({
          'status': status,
          'decididoPor': eu,
          'decididoPorNome': nome,
          'decididoEm': FieldValue.serverTimestamp(),
          'motivo': motivo,
        }),
      );

  Future<void> cancelar(Sugestao x) => _semEsperar(
    _g.collection('sugestoes').doc(x.id).update({
      'status': 'cancelada',
      'decididoEm': FieldValue.serverTimestamp(),
    }),
  );

  // ---------------- versões ----------------

  Future<List<Versao>> versoes(String songId) async {
    if (!ativa) return const [];
    final q = await _g
        .collection('musicas')
        .doc(songId)
        .collection('versoes')
        .orderBy('n', descending: true)
        .limit(100)
        .get();
    return q.docs.map(Versao.fromDoc).toList();
  }

  /// Volta a música p/ uma versão antiga (vira uma versão nova; nada se perde).
  void restaurar(Song atual, Versao v) {
    if (!podeEditarSong(atual)) return;
    final s = v.song.copy()
      ..dono = atual.dono
      ..donoNome = atual.donoNome
      ..editores = List.of(atual.editores)
      ..versao = atual.versao
      ..updatedAt = DateTime.now();
    app.applyCloudSong(s, forcar: true);
    _gravarSong(s, acao: 'voltou para a versão ${v.n}');
    app.touch();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _gruposSub?.cancel();
    _pararGrupo();
    super.dispose();
  }
}
