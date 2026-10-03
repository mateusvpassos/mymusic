import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core/chord_engine.dart';
import '../data/store.dart';
import '../models/song.dart';

/// Sessão ao vivo pela rede local (Wi-Fi ou hotspot do celular).
///
/// Um aparelho cria a sessão e vira o "hub" (servidor WebSocket); os outros
/// entram. Toda mensagem passa pelo hub, que aplica e repassa aos demais.
/// Achar a sessão é por beacon UDP em broadcast; se a rede bloquear
/// broadcast (comum em Wi-Fi de igreja/visitante), dá p/ digitar o IP.
enum LiveRole { off, host, guest }

/// conduz: o que você faz vai p/ os outros. segue: você acompanha quem
/// conduz. livre: só troca edição de música, sem acompanhar navegação.
enum LiveMode { conduz, segue, livre }

class LivePeer {
  final String id;
  String name;
  LiveMode mode;
  LivePeer(this.id, this.name, this.mode);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'mode': mode.name};
  static LivePeer fromJson(Map<String, dynamic> j) => LivePeer(
    j['id'] as String,
    j['name'] as String? ?? '?',
    LiveMode.values.asNameMap()[j['mode']] ?? LiveMode.livre,
  );
}

/// Quem conduz abriu/trocou de música ou mudou o tom.
class LiveNav {
  final String by, songId;
  final String? setlistId;
  final int transpose;
  const LiveNav(this.by, this.songId, this.setlistId, this.transpose);
}

/// Posição da rolagem de quem conduz, em fração da altura do conteúdo.
class LiveScroll {
  final String by, songId;
  final double frac;
  const LiveScroll(this.by, this.songId, this.frac);
}

class FoundHost {
  final String address;
  final int port;
  final String name;
  final int peers;
  DateTime seen;
  FoundHost(this.address, this.port, this.name, this.peers, this.seen);
}

class LiveSession extends ChangeNotifier {
  static const port = 47800; // servidor (tenta os 10 seguintes se ocupado)
  static const beaconPort = 47801;
  static const _proto = 1;

  final AppState app;
  LiveSession(this.app) {
    app.localSongHooks.add(_localSong);
    app.localSetlistHooks.add(_localSetlist);
  }

  final String myId = ChordEngine.uid();
  LiveRole role = LiveRole.off;
  LiveMode mode = LiveMode.segue;
  String? error;
  String? hostName; // nome de quem criou a sessão (visto pelo convidado)
  String? hostAddress; // ip:porta conectado (convidado)
  int? serverPort; // porta aberta (hub)
  final Map<String, LivePeer> peers = {}; // inclui este aparelho

  /// Último estado de navegação recebido — quem abre a tela da música
  /// depois usa p/ já cair no ponto certo.
  LiveNav? lastNav;
  LiveScroll? lastScroll;

  final _navCtrl = StreamController<LiveNav>.broadcast();
  final _scrollCtrl = StreamController<LiveScroll>.broadcast();
  Stream<LiveNav> get navStream => _navCtrl.stream;
  Stream<LiveScroll> get scrollStream => _scrollCtrl.stream;

  bool get active => role != LiveRole.off;
  bool get following => active && mode == LiveMode.segue;
  bool get conducting => active && mode == LiveMode.conduz;
  int get others => peers.isNotEmpty ? peers.length - 1 : 0;

  String get myName {
    final n = app.settings.deviceName.trim();
    return n.isNotEmpty
        ? n
        : 'Aparelho ${myId.substring(myId.length - 4).toUpperCase()}';
  }

  // ---- hub ----
  HttpServer? _server;
  final Map<WebSocket, String> _clients = {};
  RawDatagramSocket? _beaconSock;
  Timer? _beaconTimer;

  // ---- convidado ----
  WebSocket? _ws;
  bool _wantConnected = false;
  Timer? _retry;

  // O nome padrão vinha do id sorteado a cada abertura do app ("Aparelho
  // Y51N" virava "I5PP" depois de reiniciar). Grava na 1ª vez.
  void _fixaNome() {
    if (app.settings.deviceName.trim().isEmpty) {
      final nome = myName;
      app.updateSettings((s) => s.deviceName = nome);
    }
  }

  /// Cria a sessão neste aparelho.
  Future<bool> host() async {
    await leave();
    _fixaNome();
    error = null;
    for (var p = port; p < port + 10; p++) {
      try {
        _server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          p,
          shared: false,
        );
        serverPort = p;
        break;
      } catch (_) {
        /* porta ocupada: tenta a próxima */
      }
    }
    if (_server == null) {
      error = 'Não consegui abrir a porta da sessão';
      notifyListeners();
      return false;
    }
    role = LiveRole.host;
    mode = LiveMode.conduz;
    peers
      ..clear()
      ..[myId] = LivePeer(myId, myName, mode);
    _server!.listen(_onHttp, onError: (_) {});
    await _startBeacon();
    notifyListeners();
    return true;
  }

  Future<void> _onHttp(HttpRequest req) async {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response
        ..statusCode = HttpStatus.ok
        ..write('MyMusic ao vivo')
        ..close();
      return;
    }
    final WebSocket ws;
    try {
      ws = await WebSocketTransformer.upgrade(req);
    } catch (_) {
      return; // pedido estranho na porta: ignora
    }
    ws.pingInterval = const Duration(seconds: 4);
    _clients[ws] = '';
    ws.listen(
      (data) => _onRaw(data, ws),
      onDone: () => _dropClient(ws),
      onError: (_) => _dropClient(ws),
      cancelOnError: true,
    );
  }

  void _dropClient(WebSocket ws) {
    final id = _clients.remove(ws);
    // reconectou antes da conexão velha cair: o aparelho continua na sessão
    if (id != null && _clients.containsValue(id)) return;
    if (id != null && id.isNotEmpty) {
      final p = peers.remove(id);
      if (p != null) app.logEvent('saiu', 'sessao', p.name);
      _broadcastPeers();
      notifyListeners();
    }
  }

  // ---- beacon UDP (achar a sessão sem digitar IP) ----

  Future<void> _startBeacon() async {
    try {
      // só enviar broadcast não precisa do MulticastLock (ele mantém o Wi-Fi
      // acordando p/ todo pacote de broadcast da rede: gasta bateria)
      _beaconSock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _beaconSock!.broadcastEnabled = true;
      final alvos = <InternetAddress>{InternetAddress('255.255.255.255')};
      // broadcast da sub-rede também (alguns roteadores descartam o global)
      for (final ip in await localAddresses()) {
        final o = ip.split('.');
        if (o.length == 4)
          alvos.add(InternetAddress('${o[0]}.${o[1]}.${o[2]}.255'));
      }
      _beaconTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        final b = utf8.encode(
          jsonEncode({
            'app': 'mymusic',
            'v': _proto,
            'name': myName,
            'port': serverPort,
            'peers': peers.length,
          }),
        );
        for (final a in alvos) {
          try {
            _beaconSock?.send(b, a, beaconPort);
          } catch (_) {}
        }
      });
    } catch (_) {
      // sem broadcast ainda dá p/ entrar digitando o IP
    }
  }

  // ---- descoberta ----
  RawDatagramSocket? _discSock;
  Timer? _discTimer;
  final Map<String, FoundHost> found = {};

  Future<void> startDiscovery() async {
    if (_discSock != null) return;
    try {
      await _multicastLock(true);
      _discSock = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        beaconPort,
        reuseAddress: true,
      );
      _discSock!.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final d = _discSock?.receive();
        if (d == null) return;
        final h = parseBeacon(d.data, d.address.address);
        if (h == null) return;
        found['${h.address}:${h.port}'] = h;
        notifyListeners();
      });
      // some quem parou de anunciar
      _discTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        final limite = DateTime.now().subtract(const Duration(seconds: 7));
        final antes = found.length;
        found.removeWhere((_, h) => h.seen.isBefore(limite));
        if (found.length != antes) notifyListeners();
      });
    } catch (e) {
      error = 'Busca automática indisponível nesta rede — digite o IP';
      notifyListeners();
    }
  }

  void stopDiscovery() {
    _discTimer?.cancel();
    _discTimer = null;
    _discSock?.close();
    _discSock = null;
    found.clear();
    if (!active) _multicastLock(false);
  }

  /// Beacon -> sessão encontrada (null se não for do MyMusic).
  @visibleForTesting
  static FoundHost? parseBeacon(List<int> data, String from) {
    try {
      final j = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      if (j['app'] != 'mymusic' || j['port'] is! int) return null;
      return FoundHost(
        from,
        j['port'] as int,
        (j['name'] ?? '?') as String,
        (j['peers'] ?? 1) as int,
        DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  static const _net = MethodChannel('mymusic/net');
  static Future<void> _multicastLock(bool on) async {
    // Android descarta broadcast/multicast sem a trava; fora do Android a
    // chamada só falha e tudo segue
    try {
      await _net.invokeMethod(on ? 'acquireMulticast' : 'releaseMulticast');
    } catch (_) {}
  }

  /// IPs deste aparelho na rede local (p/ mostrar e alguém digitar).
  static Future<List<String>> localAddresses() async {
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
      return [
        for (final i in ifs)
          for (final a in i.addresses)
            if (!a.isLoopback && !a.address.startsWith('169.254')) a.address,
      ];
    } catch (_) {
      return const [];
    }
  }

  // ---- convidado ----

  /// Entra na sessão de [address] ("192.168.0.10" ou "192.168.0.10:47800").
  Future<bool> join(String address, {int? port}) async {
    await leave();
    _fixaNome();
    error = null;
    var host = address.trim();
    var p = port ?? LiveSession.port;
    final i = host.lastIndexOf(':');
    if (i > 0) {
      p = int.tryParse(host.substring(i + 1)) ?? p;
      host = host.substring(0, i);
    }
    hostAddress = '$host:$p';
    role = LiveRole.guest;
    _wantConnected = true;
    peers
      ..clear()
      ..[myId] = LivePeer(myId, myName, mode);
    notifyListeners();
    final ok = await _connect();
    if (!ok) {
      _wantConnected = false;
      role = LiveRole.off;
      hostAddress = null;
      peers.clear();
      notifyListeners();
    }
    return ok;
  }

  bool reconnecting = false;

  Future<bool> _connect() async {
    try {
      final ws = await WebSocket.connect(
        'ws://$hostAddress/live',
      ).timeout(const Duration(seconds: 5));
      ws.pingInterval = const Duration(seconds: 4);
      _ws = ws;
      reconnecting = false;
      ws.listen(
        (data) => _onRaw(data, null),
        onDone: _lostHost,
        onError: (_) => _lostHost(),
        cancelOnError: true,
      );
      _send({
        't': 'hello',
        'v': _proto,
        'id': myId,
        'name': myName,
        'mode': mode.name,
      });
      error = null;
      notifyListeners();
      return true;
    } catch (e) {
      error = 'Não achei a sessão em $hostAddress';
      notifyListeners();
      return false;
    }
  }

  // Wi-Fi de igreja cai: tenta voltar sozinho por um tempo antes de desistir
  void _lostHost() {
    _ws = null;
    if (!_wantConnected) return;
    reconnecting = true;
    peers.removeWhere((id, _) => id != myId);
    notifyListeners();
    var tentativas = 0;
    _retry?.cancel();
    _retry = Timer.periodic(const Duration(seconds: 2), (t) async {
      if (!_wantConnected || _ws != null) {
        t.cancel();
        return;
      }
      if (++tentativas > 30) {
        t.cancel();
        error = 'Conexão com a sessão perdida';
        await leave();
        return;
      }
      await _connect();
    });
  }

  /// Sai da sessão (ou encerra, se for o hub).
  Future<void> leave() async {
    _wantConnected = false;
    _retry?.cancel();
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _beaconSock?.close();
    _beaconSock = null;
    final ws = _ws;
    _ws = null;
    if (ws != null) {
      try {
        ws.add(jsonEncode({'t': 'bye', 'id': myId}));
        await ws.close();
      } catch (_) {}
    }
    for (final c in _clients.keys.toList()) {
      try {
        await c.close();
      } catch (_) {}
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
    serverPort = null;
    final era = role;
    role = LiveRole.off;
    hostAddress = null;
    hostName = null;
    reconnecting = false;
    peers.clear();
    lastNav = null;
    lastScroll = null;
    if (_discSock == null) await _multicastLock(false);
    if (era != LiveRole.off) notifyListeners();
  }

  void setMode(LiveMode m) {
    mode = m;
    peers[myId]?.mode = m;
    if (role == LiveRole.host) {
      _broadcastPeers();
    } else if (role == LiveRole.guest) {
      _send({'t': 'mode', 'id': myId, 'mode': m.name});
    }
    // um condutor por vez: quem assume avisa, e quem conduzia passa a seguir
    if (m == LiveMode.conduz && active) _send({'t': 'takeover', 'id': myId});
    notifyListeners();
  }

  /// Nome de quem tirou a condução deste aparelho (a tela avisa e limpa).
  String? perdeuConducaoPara;

  // ---- publicar (chamado pela tela da música de quem conduz) ----

  void publishNav(Song song, {Setlist? setlist, int transpose = 0}) {
    if (!conducting) return;
    _publish({
      't': 'nav',
      'by': myId,
      'songId': song.id,
      'setlistId': setlist?.id,
      'transpose': transpose,
      // vai junto: quem segue pode não ter a música (ou ter versão velha)
      'song': song.toJson(),
      if (setlist != null) 'setlist': setlist.toJson(),
    });
  }

  void publishScroll(String songId, double frac) {
    if (!conducting) return;
    _publish({'t': 'scroll', 'by': myId, 'songId': songId, 'frac': frac});
  }

  // o hub guarda o próprio estado também: quem entrar depois cai no ponto
  // em que ele está, não só no do último convidado que conduziu
  void _publish(Map<String, dynamic> m) {
    if (role == LiveRole.host) {
      if (m['t'] == 'nav') {
        lastNavRaw = m;
        lastScrollRaw = null;
      } else {
        lastScrollRaw = m;
      }
    }
    _send(m);
  }

  // com a nuvem ligada é ela que leva as edições (respeitando quem pode
  // editar); aqui só a navegação
  void _localSong(Song s) {
    if (!active || app.cloudAtiva) return;
    _send({'t': 'song', 'by': myId, 'song': s.toJson()});
  }

  void _localSetlist(Setlist sl) {
    if (!active || app.cloudAtiva) return;
    _send({'t': 'setlist', 'by': myId, 'setlist': sl.toJson()});
  }

  // ---- transporte ----

  /// Hub manda p/ todos; convidado manda p/ o hub (que repassa).
  void _send(Map<String, dynamic> m, {WebSocket? except}) {
    final raw = jsonEncode(m);
    if (role == LiveRole.host) {
      for (final c in _clients.keys) {
        if (c == except || _clients[c]!.isEmpty) continue;
        try {
          c.add(raw);
        } catch (_) {}
      }
    } else if (role == LiveRole.guest) {
      try {
        _ws?.add(raw);
      } catch (_) {}
    }
  }

  void _sendTo(WebSocket ws, Map<String, dynamic> m) {
    try {
      ws.add(jsonEncode(m));
    } catch (_) {}
  }

  void _broadcastPeers() {
    _send({
      't': 'peers',
      'host': myName,
      'peers': peers.values.map((p) => p.toJson()).toList(),
    });
  }

  void _onRaw(dynamic data, WebSocket? from) {
    // mensagem malformada (outra versão do app, rede ruim) não pode derrubar
    // a sessão: descarta e segue
    try {
      _handle(jsonDecode(data as String) as Map<String, dynamic>, from);
    } catch (e) {
      debugPrint('ao vivo: mensagem ignorada ($e)');
    }
  }

  String _nameOf(String? id) => peers[id]?.name ?? 'outro aparelho';

  void _handle(Map<String, dynamic> m, WebSocket? from) {
    final t = m['t'];

    // ---- só o hub ----
    if (role == LiveRole.host && from != null) {
      if (t == 'hello') {
        final p = LivePeer(
          m['id'] as String,
          (m['name'] ?? '?') as String,
          LiveMode.values.asNameMap()[m['mode']] ?? LiveMode.segue,
        );
        _clients[from] = p.id;
        peers[p.id] = p;
        app.logEvent('entrou', 'sessao', p.name);
        _sendTo(from, {
          't': 'welcome',
          'host': myName,
          'peers': peers.values.map((x) => x.toJson()).toList(),
          if (lastNavRaw != null) 'nav': lastNavRaw,
          if (lastScrollRaw != null) 'scroll': lastScrollRaw,
        });
        _broadcastPeers();
        notifyListeners();
        return;
      }
      if (t == 'mode') {
        peers[m['id']]?.mode =
            LiveMode.values.asNameMap()[m['mode']] ?? LiveMode.livre;
        _broadcastPeers();
        notifyListeners();
        return;
      }
      if (t == 'bye') {
        _dropClient(from);
        return;
      }
      // o resto o hub repassa aos outros e também aplica em si
      _send(m, except: from);
    }

    switch (t) {
      case 'welcome':
        hostName = m['host'] as String?;
        _setPeers(m['peers']);
        if (m['nav'] is Map) _handle(m['nav'] as Map<String, dynamic>, null);
        if (m['scroll'] is Map)
          _handle(m['scroll'] as Map<String, dynamic>, null);
        notifyListeners();
      case 'peers':
        hostName = (m['host'] as String?) ?? hostName;
        _setPeers(m['peers']);
        notifyListeners();
      case 'nav':
        lastNavRaw = m;
        final de = _nameOf(m['by'] as String?);
        if (m['song'] is Map) {
          _applySong(
            Song.fromJson(m['song'] as Map<String, dynamic>),
            de,
            from,
          );
        }
        if (m['setlist'] is Map) {
          _applySetlist(
            Setlist.fromJson(m['setlist'] as Map<String, dynamic>),
            de,
            from,
          );
        }
        final nav = LiveNav(
          m['by'] as String,
          m['songId'] as String,
          m['setlistId'] as String?,
          (m['transpose'] ?? 0) as int,
        );
        if (nav.by == myId) return;
        lastNav = nav;
        lastScroll = null;
        if (following) _navCtrl.add(nav);
        notifyListeners();
      case 'scroll':
        lastScrollRaw = m;
        final s = LiveScroll(
          m['by'] as String,
          m['songId'] as String,
          (m['frac'] as num).toDouble(),
        );
        if (s.by == myId) return;
        lastScroll = s;
        if (following) _scrollCtrl.add(s);
      case 'takeover':
        final quem = m['id'] as String?;
        if (quem != myId && mode == LiveMode.conduz) {
          perdeuConducaoPara = _nameOf(quem);
          setMode(LiveMode.segue);
        }
      case 'song':
        _applySong(
          Song.fromJson(m['song'] as Map<String, dynamic>),
          _nameOf(m['by'] as String?),
          from,
        );
      case 'setlist':
        _applySetlist(
          Setlist.fromJson(m['setlist'] as Map<String, dynamic>),
          _nameOf(m['by'] as String?),
          from,
        );
    }
  }

  // guardados crus p/ repassar a quem entrar depois
  Map<String, dynamic>? lastNavRaw, lastScrollRaw;

  void _applySong(Song s, String de, WebSocket? from) {
    if (app.cloudAtiva) return;
    final maisNova = app.applyRemoteSong(s, de: de);
    // a daqui é mais nova: devolve p/ quem mandou se corrigir
    if (maisNova != null) {
      final msg = {'t': 'song', 'by': myId, 'song': maisNova.toJson()};
      if (from != null) {
        _sendTo(from, msg);
      } else {
        _send(msg);
      }
    }
  }

  void _applySetlist(Setlist sl, String de, WebSocket? from) {
    if (app.cloudAtiva) return;
    final maisNova = app.applyRemoteSetlist(sl, de: de);
    if (maisNova != null) {
      final msg = {'t': 'setlist', 'by': myId, 'setlist': maisNova.toJson()};
      if (from != null) {
        _sendTo(from, msg);
      } else {
        _send(msg);
      }
    }
  }

  void _setPeers(dynamic list) {
    if (list is! List) return;
    peers.clear();
    for (final e in list) {
      final p = LivePeer.fromJson(e as Map<String, dynamic>);
      peers[p.id] = p;
    }
    peers.putIfAbsent(myId, () => LivePeer(myId, myName, mode));
  }

  @override
  void dispose() {
    leave();
    stopDiscovery();
    _navCtrl.close();
    _scrollCtrl.close();
    super.dispose();
  }
}
