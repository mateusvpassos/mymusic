import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/search.dart';
import '../data/store.dart';
import '../models/song.dart';
import '../ui/song_edit_page.dart';
import '../ui/song_view_page.dart';
import '../ui/widgets/chord_chart.dart';
import 'acervo.dart';
import 'cloud_state.dart';
import 'permissions_sheet.dart';
import 'versions_page.dart';

/// Acervo geral: todas as músicas (obras) de quem usa o app, com as versões.
class AcervoPage extends StatefulWidget {
  const AcervoPage({super.key});
  @override
  State<AcervoPage> createState() => _AcervoPageState();
}

class _AcervoPageState extends State<AcervoPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AcervoState>();
    final st = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final obras = a.obras;
    // busca na versão principal de cada obra (título, artista, letra)
    final principais = {for (final e in obras.entries) e.value.first.id: e.key};
    final hits = SongSearch.run(
      obras.values.map((l) => l.first),
      _q,
    );
    if (_q.trim().isEmpty) {
      hits.sort((x, y) => SongSearch.fold(x.song.title).compareTo(SongSearch.fold(y.song.title)));
    }
    final naBiblioteca = {for (final s in st.songs) s.baseId};
    return Scaffold(
      appBar: AppBar(title: const Text('Acervo geral')),
      body: !a.ligado
          ? const Center(child: Text('Entre com o Google (☁ na tela inicial) p/ ver o acervo.'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v),
                    decoration: const InputDecoration(
                      hintText: 'Buscar no acervo (nome, artista ou trecho da letra)...',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                if (!a.carregou) const LinearProgressIndicator(),
                if (a.erro != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(a.erro!, style: TextStyle(color: scheme.error)),
                  ),
                Expanded(
                  child: hits.isEmpty
                      ? Center(
                          child: Text(
                            a.carregou ? 'Nada encontrado' : 'Carregando...',
                            style: TextStyle(color: Theme.of(context).disabledColor),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                          itemCount: hits.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final s = hits[i].song;
                            final obra = principais[s.id]!;
                            final vs = obras[obra]!;
                            final tem = vs.any((v) => naBiblioteca.contains(v.id));
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(child: Text(s.key)),
                                title: Text(s.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text([
                                  if (s.artist.isNotEmpty) s.artist,
                                  'de ${a.nomeDe(s.dono)}',
                                  vs.length == 1 ? '1 versão' : '${vs.length} versões',
                                  if (hits[i].snippet != null) '“${hits[i].snippet}”',
                                ].join('  •  '), maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: tem
                                    ? Tooltip(
                                        message: 'Já está na sua biblioteca',
                                        child: Icon(Icons.library_add_check, color: scheme.primary),
                                      )
                                    : const Icon(Icons.chevron_right),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => ObraPage(obra: obra)),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

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
