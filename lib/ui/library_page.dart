import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/chord_engine.dart';
import '../cloud/acervo.dart';
import '../cloud/acervo_page.dart';
import '../cloud/cloud_page.dart';
import '../cloud/cloud_state.dart';
import '../cloud/suggestions_page.dart';
import '../core/liturgia.dart';
import '../core/search.dart';
import '../data/store.dart';
import '../live/live_page.dart';
import '../live/live_session.dart';
import '../models/song.dart';
import 'song_view_page.dart';
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
                hintText: 'Buscar...',
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
              children: [_songsTab(st), _setlistsTab(st)],
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

  Widget _songsTab(AppState st) {
    final list = SongSearch.run(st.songs, _query);
    if (list.isEmpty) return _empty('Nenhuma música', Icons.library_music);
    final uso = UsoMusicas.calcula(st.setlists);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _songCard(
        st,
        list[i].song,
        trecho: list[i].snippet,
        uso: uso[list[i].song.id],
      ),
    );
  }

  Widget _songCard(AppState st, Song s, {String? trecho, SongUse? uso}) {
    final scheme = Theme.of(context).colorScheme;
    final cloud = context.watch<CloudState>();
    final meta = <String>[
      // no grupo: de quem é (as minhas não precisam dizer)
      if (cloud.ativa && s.dono.isNotEmpty && s.dono != cloud.eu)
        'de ${cloud.nomeDe(s.dono)}',
      if (s.artist.isNotEmpty) s.artist,
      if (s.bpm > 0) '${s.bpm} BPM',
      // pelos repertórios com data já passada
      if (uso != null)
        'tocada ${UsoMusicas.quando(uso.ultima)} (${uso.vezes}x)',
    ].join('  •  ');
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        title: Text(
          s.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        subtitle: (meta.isEmpty && s.tags.isEmpty && trecho == null)
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // achou pela letra: mostra o trecho
                  if (trecho != null)
                    Text(
                      '“$trecho”',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.primary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  if (meta.isNotEmpty)
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  if (s.tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: s.tags
                            .take(4)
                            .map(
                              (t) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  t,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                ],
              ),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [scheme.primary, scheme.tertiary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(13),
          ),
          alignment: Alignment.center,
          child: Text(
            s.key,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => SongEditPage(songId: s.id)),
              );
            } else if (v == 'dup') {
              st.duplicateSong(s);
            } else if (v == 'del') {
              _confirmDelete(
                'Excluir "${s.title}"?',
                () => st.deleteSong(s.id),
              );
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'edit',
              child: Text(cloud.podeEditarSong(s) ? 'Editar' : 'Sugerir mudança'),
            ),
            const PopupMenuItem(value: 'dup', child: Text('Duplicar')),
            // no grupo só o dono apaga
            if (cloud.souDono(s.dono))
              const PopupMenuItem(value: 'del', child: Text('Excluir')),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SongViewPage(songId: s.id)),
        ),
      ),
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
        if (c.user != null)
          IconButton(
            tooltip: 'Acervo geral',
            icon: const Icon(Icons.public),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AcervoPage()),
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
          tooltip: c.ativa ? 'Grupo: ${c.grupo!.nome}' : 'Grupo compartilhado',
          icon: Icon(c.ativa ? Icons.cloud_done_outlined : Icons.cloud_off_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CloudPage()),
          ),
        ),
      ],
    );
  }
}
