import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../core/chord_engine.dart';
import '../core/diff.dart';
import '../data/store.dart';
import '../models/song.dart';
import 'cloud_state.dart';

/// Acervo geral: todas as músicas de todo mundo que usa o app.
///
/// Cada documento é UMA versão (arranjo) de uma obra: "Original",
/// "Simplificada", "Versão rcc"... Quem cria a versão é o dono; os outros
/// sugerem. A biblioteca (e o grupo) usa CÓPIAS: puxar copia a versão e
/// guarda de onde veio ([Song.baseId]/[Song.baseRev]) p/ avisar quando ela
/// mudar no acervo.
class AcervoState extends ChangeNotifier {
  final CloudState cloud;
  final AppState app;
  AcervoState(this.cloud, this.app) {
    cloud.addListener(_userMudou);
  }

  /// id da versão -> versão (só as que não foram apagadas)
  final Map<String, Song> musicas = {};
  final Map<String, List<String>> confianca = {};
  final Map<String, String> nomes = {};
  List<Sugestao> sugestoes = [];
  bool carregou = false;
  String? erro;

  final List<StreamSubscription> _subs = [];
  final Map<String, Song> _ultima = {};
  String _quem = '';

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('acervo');
  String get eu => cloud.eu;
  bool get ligado => cloud.user != null;

  String nomeDe(String email) =>
      email == eu ? cloud.nome : (nomes[email] ?? cloud.nomeDe(email));

  // ---------------- liga/desliga com o login ----------------

  void _userMudou() {
    if (eu == _quem) return;
    _quem = eu;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    musicas.clear();
    _ultima.clear();
    sugestoes = [];
    carregou = false;
    if (eu.isEmpty) {
      notifyListeners();
      return;
    }
    _subs.add(_col.snapshots().listen((q) {
      for (final ch in q.docChanges) {
        final j = ch.doc.data();
        if (j == null) continue;
        if (j['apagada'] == true || ch.type == DocumentChangeType.removed) {
          musicas.remove(ch.doc.id);
          continue;
        }
        final s = Song.fromJson(normFirestore(j));
        musicas[s.id] = s;
        if (!ch.doc.metadata.hasPendingWrites) _ultima[s.id] = s.copy();
      }
      carregou = true;
      notifyListeners();
    }, onError: _onErro));
    _subs.add(_db.collection('confianca').snapshots().listen((q) {
      confianca
        ..clear()
        ..addEntries(q.docs.map((d) => MapEntry(
              d.id,
              ((d.data()['editores'] as List?) ?? const []).cast<String>(),
            )));
      notifyListeners();
    }, onError: _onErro));
    _subs.add(_db.collection('pessoas').snapshots().listen((q) {
      nomes
        ..clear()
        ..addEntries(q.docs.map(
            (d) => MapEntry(d.id, (d.data()['nome'] ?? '') as String)));
      notifyListeners();
    }, onError: _onErro));
    final pend = <String, Sugestao>{}, minhas = <String, Sugestao>{};
    void junta() {
      sugestoes = {...minhas, ...pend}.values.toList()
        ..sort((a, b) => (b.em ?? DateTime(0)).compareTo(a.em ?? DateTime(0)));
      notifyListeners();
    }

    final sug = _db.collection('acervoSugestoes');
    _subs.add(sug.where('status', isEqualTo: 'pendente').snapshots().listen((q) {
      pend
        ..clear()
        ..addEntries(q.docs.map((d) => MapEntry(d.id, Sugestao.fromDoc(d, acervo: true))));
      junta();
    }, onError: _onErro));
    _subs.add(sug.where('por', isEqualTo: eu).snapshots().listen((q) {
      minhas
        ..clear()
        ..addEntries(q.docs.map((d) => MapEntry(d.id, Sugestao.fromDoc(d, acervo: true))));
      junta();
    }, onError: _onErro));
    // meu nome p/ os outros verem no acervo
    _semEsperar(_db.collection('pessoas').doc(eu).set({
      'nome': cloud.nome,
      'visto': FieldValue.serverTimestamp(),
    }));
  }

  void _onErro(Object e) {
    erro = '$e';
    notifyListeners();
  }

  Future<void> _semEsperar(Future<void> f) async {
    unawaited(f.catchError((Object e) {
      erro = e is FirebaseException && e.code == 'permission-denied'
          ? 'Sem permissão para essa mudança no acervo.'
          : '$e';
      notifyListeners();
    }));
  }

  // ---------------- obras e versões ----------------

  static String obraDe(Song s) => s.obra.isNotEmpty ? s.obra : s.id;

  /// obra -> versões (a mais antiga primeiro: costuma ser a original)
  Map<String, List<Song>> get obras {
    final m = <String, List<Song>>{};
    for (final s in musicas.values) {
      (m[obraDe(s)] ??= []).add(s);
    }
    for (final l in m.values) {
      l.sort((a, b) {
        if (a.id == obraDe(a)) return -1;
        if (b.id == obraDe(b)) return 1;
        return a.nomeVersao.compareTo(b.nomeVersao);
      });
    }
    return m;
  }

  List<Song> versoesDaObra(String obra) => obras[obra] ?? const [];

  static String rotulo(Song s) =>
      s.nomeVersao.isNotEmpty ? s.nomeVersao : 'Original';

  bool podeEditar(Song s) => Permissao.podeEditar(
        eu: eu,
        dono: s.dono,
        editores: s.editores,
        confianca: confianca,
      );

  bool souDono(Song s) => s.dono == eu;

  /// Grava a versão + um retrato no histórico (revisões), no mesmo lote.
  void salvar(Song s, {String? acao}) {
    if (!ligado) return;
    final antes = _ultima[s.id];
    final nova = !musicas.containsKey(s.id);
    final out = s.copy()
      ..dono = s.dono.isEmpty ? eu : s.dono
      ..donoNome = s.dono.isEmpty ? cloud.nome : s.donoNome
      ..versao = (antes?.versao ?? s.versao) + 1
      ..por = eu
      ..porNome = cloud.nome
      ..baseId = ''
      ..baseRev = 0
      ..updatedAt = DateTime.now();
    final ref = _col.doc(out.id);
    final b = _db.batch()
      ..set(ref, {...out.toJson(), 'apagada': false})
      ..set(ref.collection('versoes').doc(), {
        'n': out.versao,
        'song': out.toJson(),
        'por': eu,
        'porNome': cloud.nome,
        'em': FieldValue.serverTimestamp(),
        'acao': acao ?? (nova ? 'criou' : 'editou'),
        'resumo': antes == null ? const <String>[] : AppState.resumoMudancas(antes, out),
      });
    musicas[out.id] = out;
    _ultima[out.id] = out.copy();
    notifyListeners();
    _semEsperar(b.commit());
  }

  void apagar(Song s) {
    if (!souDono(s)) return;
    musicas.remove(s.id);
    notifyListeners();
    _semEsperar(_col.doc(s.id).update({
      'apagada': true,
      'apagadaPor': eu,
      'updatedAt': DateTime.now().toIso8601String(),
    }));
  }

  /// Publica uma música da biblioteca no acervo (vira a "Original" de uma
  /// obra nova, ou uma versão nova de [obra]). A da biblioteca passa a
  /// apontar p/ ela.
  Song publicar(Song local, {String nomeVersao = '', String obra = ''}) {
    final id = musicas.containsKey(local.id) || obra.isNotEmpty
        ? ChordEngine.uid()
        : local.id;
    final v = local.copy()
      ..id = id
      ..obra = obra.isEmpty || obra == id ? '' : obra
      ..nomeVersao = nomeVersao
      ..dono = ''
      ..donoNome = ''
      ..editores = []
      ..versao = 0
      ..notes = local.notes
      ..scrollSpeed = 0;
    salvar(v, acao: 'publicou');
    final pub = musicas[id]!;
    local
      ..baseId = id
      ..baseRev = pub.versao;
    cloud.atualizarCampos(local, {'baseId': id, 'baseRev': pub.versao});
    return pub;
  }

  /// Nova versão (arranjo) da mesma obra, a partir de [base], minha.
  Song novaVersao(Song base, String nomeVersao) {
    final v = base.copy()
      ..id = ChordEngine.uid()
      ..obra = obraDe(base)
      ..nomeVersao = nomeVersao
      ..dono = ''
      ..donoNome = ''
      ..editores = []
      ..versao = 0;
    salvar(v, acao: 'criou a versão "$nomeVersao" a partir de "${rotulo(base)}"');
    return musicas[v.id]!;
  }

  /// Músicas da biblioteca que ainda não estão no acervo (as minhas).
  List<Song> get naoPublicadas => app.songs
      .where((s) =>
          (s.baseId.isEmpty || !musicas.containsKey(s.baseId)) &&
          (s.dono.isEmpty || s.dono == eu))
      .toList();

  // ---------------- biblioteca/grupo <-> acervo ----------------

  /// Cópia da versão na biblioteca (e no grupo, se ligado). Devolve a cópia.
  Song puxar(Song v) {
    final ja = app.songs.where((s) => s.baseId == v.id).firstOrNull;
    if (ja != null) return ja;
    final c = v.copy()
      ..id = app.songById(v.id) == null ? v.id : ChordEngine.uid()
      ..dono = ''
      ..donoNome = ''
      ..editores = []
      ..versao = 0
      ..por = ''
      ..porNome = ''
      ..baseId = v.id
      ..baseRev = v.versao;
    app.upsertSong(c);
    return c;
  }

  Song? baseDe(Song local) =>
      local.baseId.isEmpty ? null : musicas[local.baseId];

  /// A versão de onde esta veio mudou no acervo depois da cópia.
  bool temNovidade(Song local) {
    final b = baseDe(local);
    return b != null && b.versao > local.baseRev;
  }

  /// Traz o conteúdo da versão do acervo p/ a cópia (mantém dono/grupo).
  void atualizarDoAcervo(Song local) {
    final b = baseDe(local);
    if (b == null) return;
    final c = b.copy()
      ..id = local.id
      ..dono = local.dono
      ..donoNome = local.donoNome
      ..editores = List.of(local.editores)
      ..versao = local.versao
      ..por = local.por
      ..porNome = local.porNome
      ..scrollSpeed = local.scrollSpeed
      ..baseId = b.id
      ..baseRev = b.versao;
    app.upsertSong(c);
  }

  // ---------------- sugestões ----------------

  List<Sugestao> get paraDecidir => sugestoes.where((x) {
        if (!x.pendente || x.por == eu) return false;
        final s = musicas[x.songId];
        return s != null && podeEditar(s);
      }).toList();

  List<Sugestao> get minhas => sugestoes.where((x) => x.por == eu).toList();

  Future<void> sugerir(Song proposta, {String nota = ''}) async {
    final atual = musicas[proposta.id];
    await _semEsperar(_db.collection('acervoSugestoes').doc().set({
      'songId': proposta.id,
      'titulo': '${proposta.title} (${rotulo(atual ?? proposta)})',
      'song': proposta.toJson(),
      'base': atual?.versao ?? 0,
      'dono': atual?.dono ?? '',
      'por': eu,
      'porNome': cloud.nome,
      'nota': nota,
      'em': FieldValue.serverTimestamp(),
      'status': 'pendente',
    }));
  }

  Future<void> aceitar(Sugestao x) async {
    final atual = musicas[x.songId];
    if (atual == null || !podeEditar(atual)) return;
    salvar(
      x.song.copy()
        ..id = atual.id
        ..obra = atual.obra
        ..nomeVersao = atual.nomeVersao
        ..dono = atual.dono
        ..donoNome = atual.donoNome
        ..editores = List.of(atual.editores)
        ..versao = atual.versao,
      acao: 'aceitou sugestão de ${x.porNome.isNotEmpty ? x.porNome : x.por}',
    );
    await _decidir(x, 'aceita');
  }

  Future<void> recusar(Sugestao x, {String motivo = ''}) =>
      _decidir(x, 'recusada', motivo: motivo);

  Future<void> _decidir(Sugestao x, String status, {String motivo = ''}) =>
      _semEsperar(_db.collection('acervoSugestoes').doc(x.id).update({
        'status': status,
        'decididoPor': eu,
        'decididoPorNome': cloud.nome,
        'decididoEm': FieldValue.serverTimestamp(),
        'motivo': motivo,
      }));

  Future<void> cancelar(Sugestao x) =>
      _semEsperar(_db.collection('acervoSugestoes').doc(x.id).update({
        'status': 'cancelada',
        'decididoEm': FieldValue.serverTimestamp(),
      }));

  // ---------------- revisões e permissões ----------------

  Future<List<Versao>> revisoes(String id) async {
    final q = await _col
        .doc(id)
        .collection('versoes')
        .orderBy('n', descending: true)
        .limit(100)
        .get();
    return q.docs.map(Versao.fromDoc).toList();
  }

  void restaurar(Song atual, Versao v) {
    if (!podeEditar(atual)) return;
    salvar(
      v.song.copy()
        ..id = atual.id
        ..obra = atual.obra
        ..nomeVersao = atual.nomeVersao
        ..dono = atual.dono
        ..donoNome = atual.donoNome
        ..editores = List.of(atual.editores)
        ..versao = atual.versao,
      acao: 'voltou para a revisão ${v.n}',
    );
  }

  Future<void> setEditores(Song s, List<String> emails) async {
    if (!souDono(s)) return;
    s.editores = List.of(emails);
    notifyListeners();
    await _semEsperar(_col.doc(s.id).update({'editores': emails}));
  }

  @override
  void dispose() {
    cloud.removeListener(_userMudou);
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
