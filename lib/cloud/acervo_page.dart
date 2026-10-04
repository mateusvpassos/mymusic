import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/store.dart';
import '../models/song.dart';
import '../ui/song_edit_page.dart';
import '../ui/song_view_page.dart';
import '../ui/widgets/chord_chart.dart';
import 'acervo.dart';
import 'cloud_state.dart';
import 'permissions_sheet.dart';
import 'versions_page.dart';

/// Uma música do acervo e suas versões (arranjos).
class ObraPage extends StatefulWidget {
  final String obra;
  final String? versaoId;
  const ObraPage({super.key, required this.obra, this.versaoId});
  @override
  State<ObraPage> createState() => _ObraPageState();
}

class _ObraPageState extends State<ObraPage> {
  String? _sel;

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AcervoState>();
    final st = context.watch<AppState>();
    final cloud = context.watch<CloudState>();
    final scheme = Theme.of(context).colorScheme;
    final vs = a.versoesDaObra(widget.obra);
    if (vs.isEmpty) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Música não encontrada')));
    }
    final v = vs.firstWhere((x) => x.id == (_sel ?? widget.versaoId), orElse: () => vs.first);
    final copia = st.songs.where((s) => s.baseId == v.id).firstOrNull;
    final pode = a.podeEditar(v);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(v.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            Text(
              '${AcervoState.rotulo(v)}  •  ${v.key}  •  de ${a.nomeDe(v.dono)}  •  revisão ${v.versao}',
              style: TextStyle(fontSize: 12, color: scheme.primary),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Histórico de revisões',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => VersionsPage(songId: v.id, acervo: true)),
            ),
          ),
          IconButton(
            tooltip: 'Dono e quem pode editar',
            icon: const Icon(Icons.manage_accounts_outlined),
            onPressed: () => showPermissions(
              context,
              titulo: '${v.title} — ${AcervoState.rotulo(v)}',
              dono: v.dono,
              editores: v.editores,
              salvar: (l) => a.setEditores(v, l),
              acervo: true,
            ),
          ),
          IconButton(
            tooltip: pode ? 'Editar esta versão' : 'Sugerir mudança',
            icon: Icon(pode ? Icons.edit_outlined : Icons.rate_review_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SongEditPage(songId: v.id, acervo: v)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final x in vs)
                ChoiceChip(
                  label: Text('${AcervoState.rotulo(x)} · ${a.nomeDe(x.dono)}'),
                  selected: x.id == v.id,
                  onSelected: (_) => setState(() => _sel = x.id),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Nova versão'),
                onPressed: () => _novaVersao(context, a, v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (v.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(v.notes, style: const TextStyle(fontStyle: FontStyle.italic)),
            ),
          ChordChart(
            song: v,
            fontSize: 17 * st.settings.fontScale,
            chordColor: scheme.primary,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: copia != null
              ? OutlinedButton.icon(
                  icon: const Icon(Icons.library_music),
                  label: Text(cloud.ativa ? 'Abrir a cópia do grupo' : 'Abrir na biblioteca'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => SongViewPage(songId: copia.id)),
                  ),
                )
              : FilledButton.icon(
                  icon: const Icon(Icons.library_add),
                  label: Text(cloud.ativa
                      ? 'Puxar esta versão para o grupo ${cloud.grupo!.nome}'
                      : 'Puxar esta versão para a biblioteca'),
                  onPressed: () {
                    final c = a.puxar(v);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('"${c.title}" (${AcervoState.rotulo(v)}) está na biblioteca'),
                    ));
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _novaVersao(BuildContext context, AcervoState a, Song base) async {
    final ctrl = TextEditingController();
    final nome = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nova versão'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nome (ex.: Simplificada, Versão rcc, Tom de Mi)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Criar')),
        ],
      ),
    );
    if (nome == null || nome.isEmpty || !context.mounted) return;
    final v = a.novaVersao(base, nome);
    setState(() => _sel = v.id);
    // abre p/ já adaptar
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SongEditPage(songId: v.id, acervo: v)),
    );
  }
}
