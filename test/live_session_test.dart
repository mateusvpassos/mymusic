// Sessão ao vivo de verdade (sockets em loopback): hub + 2 convidados.
// Sem TestWidgetsFlutterBinding de propósito: ele troca o HttpClient por um
// falso que devolve 400, e o WebSocket.connect usa o HttpClient.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymusic/data/store.dart';
import 'package:mymusic/live/live_session.dart';
import 'package:mymusic/models/song.dart';

Future<void> until(bool Function() ok, {String what = ''}) async {
  for (var i = 0; i < 100; i++) {
    if (ok()) return;
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
  fail('não aconteceu: $what');
}

Song song(String id, String title, {DateTime? at}) => Song(
      id: id,
      title: title,
      key: 'G',
      sections: [Section('Refrão', [SongLine('Glória', [Chord('G', 0)])])],
      updatedAt: at ?? DateTime(2026, 1, 1),
    );

void main() {
  late AppState aHub, aG1, aG2;
  late LiveSession hub, g1, g2;

  setUp(() async {
    aHub = AppState()..settings.deviceName = 'Hub';
    aG1 = AppState()..settings.deviceName = 'Violão';
    aG2 = AppState()..settings.deviceName = 'Teclado';
    hub = LiveSession(aHub);
    g1 = LiveSession(aG1);
    g2 = LiveSession(aG2);
    expect(await hub.host(), isTrue);
    expect(await g1.join('127.0.0.1:${hub.serverPort}'), isTrue);
    expect(await g2.join('127.0.0.1:${hub.serverPort}'), isTrue);
    await until(() => hub.peers.length == 3 && g1.peers.length == 3 && g2.peers.length == 3,
        what: 'todos se verem');
  });

  tearDown(() async {
    await g1.leave();
    await g2.leave();
    await hub.leave();
  });

  test('todos veem os 3 aparelhos pelo nome', () {
    for (final s in [hub, g1, g2]) {
      expect(s.peers.values.map((p) => p.name).toSet(), {'Hub', 'Violão', 'Teclado'});
    }
    expect(g1.hostName, 'Hub');
  });

  test('quem conduz troca de música e quem segue recebe — com a música junto', () async {
    final s = song('s1', 'Glória');
    aHub.songs.add(s);
    final got = <LiveNav>[];
    final sub = g2.navStream.listen(got.add);
    hub.publishNav(s, transpose: 2);
    await until(() => got.isNotEmpty, what: 'nav chegar');
    expect(got.single.songId, 's1');
    expect(got.single.transpose, 2);
    // g2 não tinha a música: veio no próprio aviso
    expect(aG2.songById('s1')?.title, 'Glória');
    await sub.cancel();
  });

  test('convidado conduzindo chega no outro convidado passando pelo hub', () async {
    g1.setMode(LiveMode.conduz);
    final got = <LiveNav>[];
    final sub = g2.navStream.listen(got.add);
    g1.publishNav(song('s2', 'Santo'));
    await until(() => got.isNotEmpty, what: 'nav do g1 chegar no g2');
    expect(got.single.by, g1.myId);
    expect(aHub.songById('s2'), isNotNull, reason: 'hub também aplica');
    await sub.cancel();
  });

  test('quem segue não manda nada (sem briga de quem conduz)', () async {
    // g2 está seguindo: publish é ignorado
    g2.publishNav(song('x', 'Não vai'));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(aHub.songById('x'), isNull);
  });

  test('rolagem de quem conduz chega em fração', () async {
    final got = <LiveScroll>[];
    final sub = g1.scrollStream.listen(got.add);
    hub.publishScroll('s1', 0.42);
    await until(() => got.isNotEmpty, what: 'scroll chegar');
    expect(got.single.frac, closeTo(0.42, 1e-9));
    await sub.cancel();
  });

  test('editar música em um aparelho atualiza os outros', () async {
    final s = song('s3', 'Cordeiro');
    aHub.songs.add(s);
    aG1.songs.add(song('s3', 'Cordeiro'));
    aG2.songs.add(song('s3', 'Cordeiro'));
    final editada = song('s3', 'Cordeiro de Deus')..capo = 3;
    aG1.upsertSong(editada); // gravação local -> sessão repassa
    await until(() => aG2.songById('s3')?.title == 'Cordeiro de Deus',
        what: 'edição chegar no g2');
    expect(aHub.songById('s3')?.capo, 3);
    expect(aG2.audit.first.details.join(' '), contains('Violão'),
        reason: 'histórico diz de onde veio');
  });

  test('versão mais velha não sobrescreve a nova — e a nova volta corrigindo', () async {
    aG2.songs.add(song('s4', 'Nova', at: DateTime(2026, 5, 1)));
    aHub.songs.add(song('s4', 'Velha', at: DateTime(2026, 1, 1)));
    hub.publishNav(aHub.songById('s4')!);
    await until(() => aHub.songById('s4')?.title == 'Nova',
        what: 'g2 devolver a versão nova');
    expect(aG2.songById('s4')?.title, 'Nova');
  });

  test('quem entra depois cai na música em que o hub está', () async {
    final s = song('s5', 'Ave Maria');
    aHub.songs.add(s);
    hub.publishNav(s, transpose: -1);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final a3 = AppState()..settings.deviceName = 'Baixo';
    final g3 = LiveSession(a3);
    await g3.join('127.0.0.1:${hub.serverPort}');
    await until(() => g3.lastNav != null, what: 'welcome trazer a nav');
    expect(g3.lastNav!.songId, 's5');
    expect(g3.lastNav!.transpose, -1);
    expect(a3.songById('s5')?.title, 'Ave Maria');
    await g3.leave();
  });

  test('sair atualiza a lista de todos', () async {
    await g2.leave();
    await until(() => hub.peers.length == 2 && g1.peers.length == 2, what: 'saída propagar');
    expect(aHub.audit.any((e) => e.action == 'saiu' && e.title == 'Teclado'), isTrue);
  });

  test('um condutor por vez: quem assume rebaixa o anterior', () async {
    expect(hub.mode, LiveMode.conduz);
    g1.setMode(LiveMode.conduz);
    await until(() => hub.mode == LiveMode.segue, what: 'hub passar a seguir');
    expect(hub.perdeuConducaoPara, 'Violão');
    await until(() => g2.peers.values.where((p) => p.mode == LiveMode.conduz).length == 1,
        what: 'lista de todos mostrar 1 condutor');
    // e o g2 passa a receber a navegação do g1
    final got = <LiveNav>[];
    final sub = g2.navStream.listen(got.add);
    g1.publishNav(song('t1', 'Aleluia'));
    await until(() => got.isNotEmpty, what: 'nav do novo condutor');
    await sub.cancel();
  });

  test('hub cai e volta: convidado reconecta sozinho', () async {
    final porta = hub.serverPort;
    await hub.leave(); // Wi-Fi caiu / app do hub fechou
    await until(() => g1.reconnecting, what: 'g1 perceber a queda');
    expect(g1.active, isTrue, reason: 'continua tentando, não sai da sessão');
    // hub volta na mesma porta
    expect(await hub.host(), isTrue);
    expect(hub.serverPort, porta);
    await until(() => !g1.reconnecting && hub.peers.containsKey(g1.myId),
        what: 'g1 voltar sozinho');
    expect(g1.hostName, 'Hub');
  });

  test('nome padrão fica gravado (não muda a cada abertura)', () async {
    final a = AppState();
    final s1 = LiveSession(a);
    await s1.host();
    final nome = a.settings.deviceName;
    expect(nome, startsWith('Aparelho '));
    await s1.leave();
    final s2 = LiveSession(a); // "reabriu o app"
    expect(s2.myName, nome);
  });

  test('baixar backup de outro aparelho não troca o nome deste', () {
    final a = AppState()..settings.deviceName = 'Violão';
    final b = AppState()..settings.deviceName = 'Teclado';
    a.importJson(b.exportJson(), replace: true);
    expect(a.settings.deviceName, 'Violão');
  });

  test('mensagem malformada não derruba a sessão', () async {
    final ws = await WebSocket.connect('ws://127.0.0.1:${hub.serverPort}/live');
    ws.add('isso não é json');
    ws.add(jsonEncode({'t': 'nav', 'songId': null})); // campo faltando
    ws.add(jsonEncode({'t': 'song', 'song': {'id': 1}}));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await ws.close();
    // continua funcionando p/ quem é de verdade
    final got = <LiveScroll>[];
    final sub = g1.scrollStream.listen(got.add);
    hub.publishScroll('x', 0.5);
    await until(() => got.isNotEmpty, what: 'sessão seguir viva');
    await sub.cancel();
  });

  test('beacon: só aceita o do MyMusic', () {
    final ok = LiveSession.parseBeacon(
        utf8.encode(jsonEncode({'app': 'mymusic', 'v': 1, 'name': 'Hub', 'port': 47800, 'peers': 2})),
        '192.168.0.9');
    expect(ok?.address, '192.168.0.9');
    expect(ok?.port, 47800);
    expect(LiveSession.parseBeacon(utf8.encode('{"app":"outro","port":1}'), 'x'), isNull);
    expect(LiveSession.parseBeacon([0, 1, 2], 'x'), isNull);
  });
}
