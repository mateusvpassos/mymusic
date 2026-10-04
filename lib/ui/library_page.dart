import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/chord_engine.dart';
import '../cloud/acervo.dart';
import '../cloud/acervo_page.dart' show ObraPage;
import '../cloud/cloud_page.dart';
import '../cloud/cloud_state.dart';
import '../cloud/suggestions_page.dart';
import '../core/liturgia.dart';
import '../core/search.dart';
import '../data/store.dart';
import '../live/live_page.dart';
import '../live/live_session.dart';
import '../models/song.dart';
import 'minhas_page.dart';
import 'song_view_page.dart';
import 'widgets/song_tile.dart';
import 'song_edit_page.dart';
import 'setlist_page.dart';
import 'settings_page.dart';

/// Botão "pílula" com gradiente (usado como FAB).
class _GradientButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _GradientButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(20);
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [scheme.primary, scheme.tertiary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Atalho p/ a sessão ao vivo; acende e mostra quantos aparelhos há quando ativa.
class _LiveButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final live = context.watch<LiveSession>();
    final scheme = Theme.of(context).colorScheme;
    final icon = Icon(
      live.active ? Icons.wifi_tethering : Icons.wifi_tethering_off,
      color: live.active
          ? (live.reconnecting ? scheme.error : scheme.primary)
          : null,
    );
    return IconButton(
      tooltip: 'Ao vivo',
      icon: live.active
          ? Badge(label: Text('${live.peers.length}'), child: icon)
          : icon,
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LivePage()),
      ),
    );
  }
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  String _query = '';

  @override
  void initState() {
    super.initState();
    // se a leitura do acervo tinha sido negada, tenta de novo ao abrir
    final a = context.read<AcervoState>();
    if (a.erro != null || !a.carregou) a.religar();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    if (!st.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset('assets/icon/icon.png', width: 32, height: 32),
            ),
            const SizedBox(width: 10),
            const Text('MyMusic'),
          ],
        ),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Músicas'),
            Tab(text: 'Repertórios'),
          ],
        ),
        actions: [
          const _CloudButtons(),
          _LiveButton(),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Configurações',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Buscar no acervo ou nos repertórios...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [_acervoTab(st), _setlistsTab(st)],
            ),
          ),
        ],
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tab,
        builder: (_, _) => _GradientButton(
          icon: Icons.add,
          label: _tab.index == 0 ? 'Música' : 'Repertório',
          onTap: () => _tab.index == 0 ? _newSong(st) : _newSetlist(st),
        ),
      ),
    );
  }

  /// Aba Músicas = acervo geral: uma linha por obra (a versão principal).
  /// Tocar abre a MINHA cópia (tom, anotações, repertórios); sem cópia, a do acervo.
  Widget _acervoTab(AppState st) {
    final a = context.watch<AcervoState>();
    final cloud = context.watch<CloudState>();
    final scheme = Theme.of(context).colorScheme;
    if (!a.ligado) {
      return _empty('Entre com o Google (ícone de pessoas lá em cima)', Icons.public);
    }
    final obras = a.obras;
    final obraDaPrincipal = {for (final e in obras.entries) e.value.first.id: e.key};
    final hits = SongSearch.run(obras.values.map((l) => l.first), _query);
    if (_query.trim().isEmpty) {
      hits.sort((x, y) => SongSearch.fold(x.song.title).compareTo(SongSearch.fold(y.song.title)));
    }
    final uso = UsoMusicas.calcula(st.setlists);
    return Column(
      children: [
        if (!a.carregou) const LinearProgressIndicator(),
        if (a.erro != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(child: Text(a.erro!, style: TextStyle(color: scheme.error))),
                TextButton(onPressed: a.religar, child: const Text('Tentar de novo')),
              ],
            ),
          ),
        Expanded(
          child: hits.isEmpty
              ? _empty(a.carregou ? (_query.isEmpty ? 'Nenhuma música no acervo' : 'Nada encontrado') : 'Carregando...',
                  Icons.library_music)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                  itemCount: hits.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final v = hits[i].song;
                    final obra = obraDaPrincipal[v.id]!;
                    final n = obras[obra]!.length;
                    final copia = a.copiaDaObra(obra);
                    final u = copia == null ? null : uso[copia.id];
                    return SongTile(
                      title: v.title,
                      keyLabel: v.key,
                      trecho: hits[i].snippet,
                      tags: v.tags,
                      meta: [
                        if (v.artist.isNotEmpty) v.artist,
                        if (v.dono.isNotEmpty && v.dono != cloud.eu) 'de ${a.nomeDe(v.dono)}',
                        if (n > 1) '$n versões',
                        if (u != null) 'tocada ${UsoMusicas.quando(u.ultima)} (${u.vezes}x)',
                      ].join('  •  '),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => SongViewPage(songId: copia?.id ?? v.id)),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (copia != null)
                            Tooltip(
                              message: 'Está nas suas músicas',
                              child: Icon(Icons.library_add_check, color: scheme.primary),
                            ),
                          PopupMenuButton<String>(
                            onSelected: (op) {
                              if (op == 'add') {
                                final c = a.puxar(v);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('"${c.title}" está nas suas músicas')),
                                );
                              } else if (op == 'versoes') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => ObraPage(obra: obra)),
                                );
                              } else if (op == 'edit') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => SongEditPage(songId: v.id, acervo: v),
                                  ),
                                );
                              }
                            },
                            itemBuilder: (_) => [
                              if (copia == null)
                                const PopupMenuItem(value: 'add', child: Text('Adicionar às minhas músicas')),
                              PopupMenuItem(
                                value: 'versoes',
                                child: Text(n > 1 ? 'Ver versões' : 'Versões e detalhes'),
                              ),
                              PopupMenuItem(
                                value: 'edit',
                                child: Text(a.podeEditar(v)
                                    ? 'Editar (${AcervoState.rotulo(v)})'
                                    : 'Sugerir mudança'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _setlistsTab(AppState st) {
    if (st.setlists.isEmpty) {
      return _empty('Nenhum repertório', Icons.queue_music);
    }
    final q = SongSearch.fold(_query.trim());
    // com data primeiro (mais recente no topo), depois sem data
    final list =
        [
          ...st.setlists.where(
            (x) => q.isEmpty || SongSearch.fold(x.name).contains(q),
          ),
        ]..sort((a, b) {
          if (a.date != null && b.date != null) {
            return b.date!.compareTo(a.date!);
          }
          if (a.date != null) return -1;
          if (b.date != null) return 1;
          return b.updatedAt.compareTo(a.updatedAt);
        });
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final sl = list[i];
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            leading: const Icon(Icons.queue_music),
            title: Text(
              sl.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
            ),
            subtitle: Builder(
              builder: (context) {
                final c = context.watch<CloudState>();
                return Text(
                  [
                    if (sl.date != null) _fmtDate(sl.date!),
                    '${sl.songIds.length} músicas',
                    if (c.ativa && sl.dono.isNotEmpty && sl.dono != c.eu)
                      'de ${c.nomeDe(sl.dono)}',
                  ].join('  •  '),
                );
              },
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'dup') st.duplicateSetlist(sl);
                if (v == 'del') {
                  _confirmDelete(
                    'Excluir "${sl.name}"?',
                    () => st.deleteSetlist(sl.id),
                  );
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'dup', child: Text('Duplicar')),
                // no grupo só o dono apaga
                if (context.read<CloudState>().souDono(sl.dono))
                  const PopupMenuItem(value: 'del', child: Text('Excluir')),
              ],
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SetlistPage(setlistId: sl.id)),
            ),
          ),
        );
      },
    );
  }

  Widget _empty(String msg, IconData icon) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 64, color: Theme.of(context).disabledColor),
        const SizedBox(height: 12),
        Text(msg, style: TextStyle(color: Theme.of(context).disabledColor)),
      ],
    ),
  );

  void _newSong(AppState st) {
    final s = Song(id: ChordEngine.uid(), title: 'Nova música');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SongEditPage(songId: s.id, novo: s),
      ),
    );
  }

  void _newSetlist(AppState st) async {
    final ctrl = TextEditingController();
    // já nasce com a data da próxima Missa de domingo: é o que dá o tempo
    // litúrgico das sugestões e o histórico de "tocada há X semanas"
    final hoje = DateTime.now();
    var data = DateTime(
      hoje.year,
      hoje.month,
      hoje.day,
    ).add(Duration(days: (7 - hoje.weekday) % 7));
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    final name = await showDialog<String>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          title: const Text('Novo repertório'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Nome'),
                onSubmitted: (v) => Navigator.pop(context, v),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(fmt(data)),
                subtitle: Text(Liturgia.temposDe(data).first),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: data,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setDlg(() => data = d);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Criar'),
            ),
          ],
        ),
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      st.upsertSetlist(
        Setlist(id: ChordEngine.uid(), name: name.trim(), date: data),
      );
    }
  }

  void _confirmDelete(String msg, VoidCallback onYes) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              onYes();
            },
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }
}

/// Nuvem: sugestões esperando (com contador) e o grupo.
class _CloudButtons extends StatelessWidget {
  const _CloudButtons();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CloudState>();
    final a = context.watch<AcervoState>();
    if (!c.disponivel) return const SizedBox.shrink();
    final n = c.paraDecidir.length + a.paraDecidir.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (c.ativa)
          IconButton(
            tooltip: 'Minhas músicas',
            icon: const Icon(Icons.library_music_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MinhasMusicasPage()),
            ),
          ),
        if (c.user != null)
          IconButton(
            tooltip: 'Sugestões',
            icon: Badge(
              isLabelVisible: n > 0,
              label: Text('$n'),
              child: const Icon(Icons.inbox_outlined),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SuggestionsPage()),
            ),
          ),
        IconButton(
          tooltip: 'Conta e compartilhamento',
          icon: Icon(c.ativa ? Icons.group_outlined : Icons.cloud_off_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CloudPage()),
          ),
        ),
      ],
    );
  }
}
