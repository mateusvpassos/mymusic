import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/store.dart';
import 'live_session.dart';

/// Criar / entrar numa sessão ao vivo e escolher se este aparelho conduz ou segue.
class LivePage extends StatefulWidget {
  const LivePage({super.key});
  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  List<String> _ips = const [];
  late final LiveSession _live = context.read<LiveSession>();

  @override
  void initState() {
    super.initState();
    if (!_live.active) _live.startDiscovery();
    LiveSession.localAddresses().then((v) {
      if (mounted) setState(() => _ips = v);
    });
  }

  @override
  void dispose() {
    _live.stopDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = context.watch<LiveSession>();
    return Scaffold(
      appBar: AppBar(title: const Text('Ao vivo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _nome(context),
          const SizedBox(height: 12),
          if (live.error != null) _erro(context, live.error!),
          if (!live.active) ..._desligado(context, live) else ..._ligado(context, live),
          const SizedBox(height: 20),
          _ajuda(context),
        ],
      ),
    );
  }

  // ---- fora de sessão ----

  List<Widget> _desligado(BuildContext context, LiveSession live) {
    final scheme = Theme.of(context).colorScheme;
    final achados = live.found.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    return [
      _GrandeBotao(
        icon: Icons.wifi_tethering,
        titulo: 'Criar sessão',
        sub: 'Este aparelho conduz: troca de música, tom e rolagem vão p/ os outros',
        onTap: () => live.host(),
      ),
      const SizedBox(height: 18),
      Row(children: [
        Text('Sessões na rede', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 10),
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
      const SizedBox(height: 8),
      if (achados.isEmpty)
        Text('Procurando... (a sessão precisa estar criada em outro aparelho na mesma rede)',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13))
      else
        for (final h in achados)
          Card(
            child: ListTile(
              leading: const Icon(Icons.tablet_android),
              title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${h.address}  •  ${h.peers} aparelho(s)'),
              trailing: FilledButton(
                onPressed: () => _entrar(live, '${h.address}:${h.port}'),
                child: const Text('Entrar'),
              ),
            ),
          ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.keyboard),
          label: const Text('Digitar endereço'),
          onPressed: () => _digitar(live),
        ),
      ),
    ];
  }

  Future<void> _entrar(LiveSession live, String addr) async {
    final ok = await live.join(addr);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conectado — seguindo quem conduz')));
    }
  }

  Future<void> _digitar(LiveSession live) async {
    final ctrl = TextEditingController();
    final addr = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Endereço da sessão'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'ex.: 192.168.0.12'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Entrar')),
        ],
      ),
    );
    if (addr != null && addr.trim().isNotEmpty) await _entrar(live, addr);
  }

  // ---- em sessão ----

  List<Widget> _ligado(BuildContext context, LiveSession live) {
    final scheme = Theme.of(context).colorScheme;
    final hub = live.role == LiveRole.host;
    final status = hub
        ? 'Sessão criada aqui'
        : live.reconnecting
            ? 'Reconectando a ${live.hostName ?? live.hostAddress}...'
            : 'Conectado a ${live.hostName ?? live.hostAddress}';
    return [
      Card(
        color: scheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(live.reconnecting ? Icons.wifi_off : Icons.wifi_tethering,
                color: scheme.onPrimaryContainer, size: 32),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(status,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16, color: scheme.onPrimaryContainer)),
                if (hub && _ips.isNotEmpty)
                  Text('Endereço p/ digitar: ${_ips.join('  ou  ')}',
                      style: TextStyle(color: scheme.onPrimaryContainer)),
              ]),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Text('Este aparelho', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      SegmentedButton<LiveMode>(
        segments: const [
          ButtonSegment(value: LiveMode.conduz, icon: Icon(Icons.campaign), label: Text('Conduz')),
          ButtonSegment(value: LiveMode.segue, icon: Icon(Icons.visibility), label: Text('Segue')),
          ButtonSegment(value: LiveMode.livre, icon: Icon(Icons.do_not_disturb_on_outlined), label: Text('Livre')),
        ],
        selected: {live.mode},
        onSelectionChanged: (s) => live.setMode(s.first),
      ),
      const SizedBox(height: 6),
      Text(
        switch (live.mode) {
          LiveMode.conduz => 'O que você abrir, o tom e a rolagem aparecem nos que seguem.',
          LiveMode.segue => 'Você acompanha quem conduz: música, tom e rolagem.',
          LiveMode.livre => 'Você navega sozinho. Edições de música continuam chegando.',
        },
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
      ),
      const SizedBox(height: 18),
      Text('Aparelhos (${live.peers.length})', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      for (final p in live.peers.values)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(switch (p.mode) {
            LiveMode.conduz => Icons.campaign,
            LiveMode.segue => Icons.visibility,
            LiveMode.livre => Icons.do_not_disturb_on_outlined,
          }),
          title: Text(p.id == live.myId ? '${p.name} (este)' : p.name),
          subtitle: Text(switch (p.mode) {
            LiveMode.conduz => 'conduz',
            LiveMode.segue => 'segue',
            LiveMode.livre => 'livre',
          }),
        ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        icon: Icon(hub ? Icons.stop_circle_outlined : Icons.logout),
        label: Text(hub ? 'Encerrar sessão' : 'Sair da sessão'),
        onPressed: () async {
          await live.leave();
          live.startDiscovery();
        },
      ),
    ];
  }

  // ---- comuns ----

  Widget _nome(BuildContext context) {
    final st = context.watch<AppState>();
    final live = context.watch<LiveSession>();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.badge_outlined),
      title: Text(live.myName, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: const Text('Nome deste aparelho na sessão'),
      trailing: IconButton(
        icon: const Icon(Icons.edit_outlined),
        tooltip: 'Mudar nome',
        onPressed: () async {
          final ctrl = TextEditingController(text: st.settings.deviceName);
          final v = await showDialog<String>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Nome do aparelho'),
              content: TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'ex.: Violão do Mateus'),
                onSubmitted: (v) => Navigator.pop(context, v),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Salvar')),
              ],
            ),
          );
          if (v != null) st.updateSettings((s) => s.deviceName = v.trim());
        },
      ),
    );
  }

  Widget _erro(BuildContext context, String msg) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ]),
      );

  Widget _ajuda(BuildContext context) => Text(
        'Todos precisam estar na mesma rede Wi-Fi (pode ser o roteador do celular). '
        'Se a sessão não aparecer na lista, a rede bloqueia a busca: use "Digitar '
        'endereço" com o número que aparece no aparelho que criou a sessão.\n\n'
        'Editar uma música ou repertório em qualquer aparelho atualiza os outros. '
        'Excluir só apaga no próprio aparelho.',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
      );
}

class _GrandeBotao extends StatelessWidget {
  final IconData icon;
  final String titulo, sub;
  final VoidCallback onTap;
  const _GrandeBotao({required this.icon, required this.titulo, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Icon(icon, size: 36, color: scheme.onPrimaryContainer),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titulo,
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800, color: scheme.onPrimaryContainer)),
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(color: scheme.onPrimaryContainer)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
