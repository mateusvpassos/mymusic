import '../cloud/cloud_page.dart';
import '../cloud/cloud_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/pedal.dart';
import '../data/store.dart';
import '../sync/drive_sync.dart';
import 'audit_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const _seeds = [
    0xFF3D5AFE, 0xFF00897B, 0xFF7E57C2, 0xFFD81B60,
    0xFFF4511E, 0xFF43A047, 0xFF1E88E5, 0xFF8D6E63,
  ];

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.settings;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card('Aparência', [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tema escuro'),
              value: s.dark,
              onChanged: (v) => st.updateSettings((x) => x.dark = v),
            ),
            const SizedBox(height: 4),
            const Text('Cor do tema'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in _seeds)
                  GestureDetector(
                    onTap: () => st.updateSettings((x) => x.seedColor = c),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: s.seedColor == c ? scheme.onSurface : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: s.seedColor == c
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Tamanho da letra: ${(s.fontScale * 100).round()}%'),
            Slider(
              // mesma faixa do A-/A+ da tela da música: valor fora da faixa
              // derruba o Slider
              min: 0.7,
              max: 2.8,
              divisions: 21,
              value: s.fontScale.clamp(0.7, 2.8),
              label: '${(s.fontScale * 100).round()}%',
              onChanged: (v) => st.updateSettings((x) => x.fontScale = v),
            ),
            Text('Velocidade auto-rolagem: ${s.scrollSpeed.round()}'),
            Slider(
              min: 8,
              max: 80,
              divisions: 18,
              value: s.scrollSpeed.clamp(8, 80),
              label: s.scrollSpeed.round().toString(),
              onChanged: (v) => st.updateSettings((x) => x.scrollSpeed = v),
            ),
          ]),
          _card('Pedal', [
            Text(
              'Toque em "Gravar" e pressione a tecla do pedal. A maioria dos pedais '
              'já funciona com os padrões (avançar/voltar).',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 4),
            _pedalRow(context, st, 'next', 'Avançar / rolar'),
            _pedalRow(context, st, 'prev', 'Voltar'),
            const SizedBox(height: 12),
            Text('Quanto cada toque rola: ${(s.pageStep * 100).round()}% da tela'),
            Slider(
              min: 0.1,
              max: 1.0,
              divisions: 18,
              value: s.pageStep.clamp(0.1, 1.0),
              label: '${(s.pageStep * 100).round()}%',
              onChanged: (v) => st.updateSettings((x) => x.pageStep = v),
            ),
            Text(
              'Menor = rola poucas linhas por toque. No fim da música o toque '
              'seguinte passa p/ a próxima do repertório.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ]),
          _card('Backup', [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.upload_file),
              title: const Text('Exportar (JSON)'),
              subtitle: const Text('Copia tudo e salva arquivo'),
              onTap: () => _export(context, st),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.download),
              title: const Text('Importar (JSON)'),
              subtitle: const Text('Cola o backup'),
              onTap: () => _import(context, st),
            ),
          ]),
          _card('Histórico', [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history),
              title: const Text('Ver histórico'),
              subtitle: Text(st.audit.isEmpty
                  ? 'Nada registrado ainda'
                  : '${st.audit.length} registro(s)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AuditPage())),
            ),
          ]),
          _card('Grupo compartilhado (nuvem)', [
            Builder(builder: (context) {
              final c = context.watch<CloudState>();
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(c.ativa ? Icons.cloud_done : Icons.cloud_off),
                title: Text(c.ativa ? c.grupo!.nome : 'Não conectado'),
                subtitle: Text(!c.disponivel
                    ? 'Ainda não configurada'
                    : c.ativa
                        ? '${c.nome} • as músicas sincronizam pelo grupo'
                        : 'Dono, sugestões, versões e permissões'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const CloudPage())),
              );
            }),
          ]),
          _card('Google Drive', [_drive(context, st)]),
          const SizedBox(height: 16),
          Center(
            child: Text('MyMusic', style: TextStyle(color: Theme.of(context).hintColor)),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [_header(title), ...children],
            ),
          ),
        ),
      );

  Widget _pedalRow(BuildContext context, AppState st, String action, String label) {
    final keys = Pedal.keysFor(st.settings, action);
    final names = keys.map(Pedal.label).take(4).join(', ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(names, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: FilledButton.tonal(
        onPressed: () => _capture(context, st, action),
        child: const Text('Gravar'),
      ),
    );
  }

  void _capture(BuildContext context, AppState st, String action) {
    final fn = FocusNode();
    showDialog(
      context: context,
      builder: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => fn.requestFocus());
        return AlertDialog(
          title: const Text('Pressione a tecla do pedal'),
          content: Focus(
            focusNode: fn,
            autofocus: true,
            onKeyEvent: (_, e) {
              if (e is KeyDownEvent) {
                st.updateSettings((x) => x.pedalKeys[action] = [e.logicalKey.keyId]);
                Navigator.pop(context);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: const SizedBox(
              height: 60,
              child: Center(child: Icon(Icons.keyboard, size: 40)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                st.updateSettings((x) => x.pedalKeys.remove(action));
                Navigator.pop(context);
              },
              child: const Text('Restaurar padrão'),
            ),
          ],
        );
      },
    ).then((_) => fn.dispose());
  }

  Widget _drive(BuildContext context, AppState st) {
    final sync = context.watch<SyncState>();
    if (!sync.signedIn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sync.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Erro: ${sync.error}',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
          FilledButton.icon(
            onPressed: sync.busy ? null : () => sync.signIn(),
            icon: const Icon(Icons.login),
            label: const Text('Entrar com Google'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.account_circle),
          title: Text(sync.email),
          subtitle: sync.lastSync == null
              ? const Text('Ainda não sincronizado')
              : Text('Último sync: ${_fmt(sync.lastSync!)}'),
          trailing: TextButton(onPressed: () => sync.signOut(), child: const Text('Sair')),
        ),
        if (sync.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Erro: ${sync.error}',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Sync automático'),
          subtitle: const Text('Ao salvar, busca o que mudou no Drive e envia o daqui'),
          value: sync.autoSync,
          onChanged: (v) => sync.setAutoSync(v),
        ),
        FilledButton.icon(
          onPressed: sync.busy ? null : () => _doSync(context, () => sync.sync(st), 'Sincronizado'),
          icon: const Icon(Icons.sync),
          label: const Text('Sincronizar agora'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: sync.busy ? null : () => _doSync(context, () => sync.upload(st), 'Enviado'),
                icon: const Icon(Icons.cloud_upload),
                label: const Text('Enviar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: sync.busy ? null : () => _confirmDownload(context, st, sync),
                icon: const Icon(Icons.cloud_download),
                label: const Text('Baixar'),
              ),
            ),
          ],
        ),
        if (sync.busy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  void _doSync(BuildContext context, Future<bool> Function() op, String okMsg) async {
    final ok = await op();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? okMsg : 'Falhou')),
    );
  }

  void _confirmDownload(BuildContext context, AppState st, SyncState sync) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Baixar do Drive'),
        content: const Text('Substitui a biblioteca local pela do Drive. Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Baixar')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    _doSync(context, () => sync.download(st), 'Biblioteca atualizada');
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  void _export(BuildContext context, AppState st) async {
    final json = st.exportJson();
    await Clipboard.setData(ClipboardData(text: json));
    final path = await st.writeBackupFile();
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Backup exportado'),
        content: Text(
            '${st.songs.length} músicas · ${st.setlists.length} repertórios.\n\n'
            'Copiado p/ área de transferência.\nArquivo salvo em:\n$path'),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  void _import(BuildContext context, AppState st) async {
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Importar backup'),
        content: SizedBox(
          width: 600,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 12,
            style: const TextStyle(fontFamily: 'ChordMono', fontSize: 12),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Cole o JSON do backup...',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, 'replace'),
              child: const Text('Substituir tudo')),
          FilledButton(
              onPressed: () => Navigator.pop(context, 'merge'),
              child: const Text('Mesclar')),
        ],
      ),
    );
    if (res == null || ctrl.text.trim().isEmpty) return;
    try {
      final n = st.importJson(ctrl.text, replace: res == 'replace');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$n músicas importadas')));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('JSON inválido')));
    }
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      );
}
