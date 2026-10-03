import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/store.dart';
import '../ui/widgets/chord_chart.dart';
import 'cloud_state.dart';
import 'diff_view.dart';

/// Histórico da música: cada gravação, quem fez e o que mudou.
class VersionsPage extends StatefulWidget {
  final String songId;
  const VersionsPage({super.key, required this.songId});
  @override
  State<VersionsPage> createState() => _VersionsPageState();
}

class _VersionsPageState extends State<VersionsPage> {
  late Future<List<Versao>> _f = context.read<CloudState>().versoes(
    widget.songId,
  );

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final c = context.watch<CloudState>();
    final s = st.songById(widget.songId);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(s == null ? 'Histórico' : 'Histórico — ${s.title}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _f = c.versoes(widget.songId)),
          ),
        ],
      ),
      body: FutureBuilder<List<Versao>>(
        future: _f,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final l = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (s != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    'Dono: ${c.nomeDe(s.dono)}'
                    '${s.editores.isNotEmpty ? '  •  podem editar: ${s.editores.map(c.nomeDe).join(', ')}' : ''}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              if (l.isEmpty) const Text('Sem versões guardadas ainda.'),
              for (final v in l)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: v.n == s?.versao ? scheme.primary : null,
                      foregroundColor: v.n == s?.versao
                          ? scheme.onPrimary
                          : null,
                      child: Text('${v.n}'),
                    ),
                    title: Text(
                      '${v.porNome.isNotEmpty ? v.porNome : v.por} ${v.acao}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      [
                        fmtQuando(v.em),
                        if (v.n == s?.versao) 'versão atual',
                        ...v.resumo,
                      ].join('\n'),
                    ),
                    isThreeLine: v.resumo.isNotEmpty,
                    onTap: s == null
                        ? null
                        : () =>
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      _VersaoPage(v: v, songId: s.id),
                                ),
                              ).then(
                                (_) => setState(
                                  () => _f = c.versoes(widget.songId),
                                ),
                              ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _VersaoPage extends StatefulWidget {
  final Versao v;
  final String songId;
  const _VersaoPage({required this.v, required this.songId});
  @override
  State<_VersaoPage> createState() => _VersaoPageState();
}

class _VersaoPageState extends State<_VersaoPage> {
  bool _diff = true;

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final c = context.watch<CloudState>();
    final atual = st.songById(widget.songId);
    final v = widget.v;
    final scheme = Theme.of(context).colorScheme;
    final pode = atual != null && c.podeEditarSong(atual);
    final eAtual = atual?.versao == v.n;
    return Scaffold(
      appBar: AppBar(
        title: Text('Versão ${v.n}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Diferença p/ atual')),
                ButtonSegment(value: false, label: Text('Cifra desta versão')),
              ],
              selected: {_diff},
              onSelectionChanged: (x) => setState(() => _diff = x.first),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Text(
            '${v.porNome.isNotEmpty ? v.porNome : v.por} ${v.acao} — ${fmtQuando(v.em)}',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (_diff)
            atual == null
                ? const Text('A música não existe mais.')
                : eAtual
                ? const Text('Esta é a versão atual.')
                : DiffView(antes: atual, depois: v.song)
          else
            ChordChart(song: v.song, fontSize: 16, chordColor: scheme.primary),
        ],
      ),
      bottomNavigationBar: atual == null || eAtual
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  icon: Icon(pode ? Icons.restore : Icons.outgoing_mail),
                  label: Text(
                    pode
                        ? 'Voltar para esta versão'
                        : 'Sugerir voltar para esta versão',
                  ),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text(
                          pode
                              ? 'Voltar para a versão ${v.n}?'
                              : 'Sugerir a versão ${v.n}?',
                        ),
                        content: Text(
                          pode
                              ? 'A música fica igual a esta versão. A atual continua no '
                                    'histórico — dá para voltar de novo.'
                              : 'O dono (${c.nomeDe(atual.dono)}) decide se aceita.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancelar'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Confirmar'),
                          ),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    if (pode) {
                      c.restaurar(atual, v);
                    } else {
                      await c.sugerir(
                        v.song.copy()..id = atual.id,
                        nota: 'Voltar para a versão ${v.n}',
                      );
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ),
            ),
    );
  }
}
