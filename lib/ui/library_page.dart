import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/chord_engine.dart';
import '../data/store.dart';
import '../models/song.dart';
import 'song_view_page.dart';
import 'song_edit_page.dart';
import 'setlist_page.dart';
import 'settings_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> with SingleTickerProviderStateMixin {
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
        title: const Text('MyMusic', style: TextStyle(fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tab,
          tabs: const [Tab(text: 'Músicas'), Tab(text: 'Repertórios')],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Configurações',
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
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
        builder: (_, __) => FloatingActionButton.extended(
          onPressed: () => _tab.index == 0 ? _newSong(st) : _newSetlist(st),
          icon: const Icon(Icons.add),
          label: Text(_tab.index == 0 ? 'Música' : 'Repertório'),
        ),
      ),
    );
  }

  Widget _songsTab(AppState st) {
    final list = st.songs
        .where((s) =>
            _query.isEmpty ||
            s.title.toLowerCase().contains(_query) ||
            s.artist.toLowerCase().contains(_query) ||
            s.tags.any((t) => t.toLowerCase().contains(_query)))
        .toList();
    if (list.isEmpty) return _empty('Nenhuma música', Icons.library_music);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _songCard(st, list[i]),
    );
  }

  Widget _songCard(AppState st, Song s) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        title: Text(s.title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
        subtitle: s.artist.isEmpty ? null : Text(s.artist),
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Text(s.key,
              style: TextStyle(
                  color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700)),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit') {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => SongEditPage(songId: s.id)));
            } else if (v == 'dup') {
              st.duplicateSong(s);
            } else if (v == 'del') {
              _confirmDelete('Excluir "${s.title}"?', () => st.deleteSong(s.id));
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Editar')),
            PopupMenuItem(value: 'dup', child: Text('Duplicar')),
            PopupMenuItem(value: 'del', child: Text('Excluir')),
          ],
        ),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => SongViewPage(songId: s.id))),
      ),
    );
  }

  Widget _setlistsTab(AppState st) {
    if (st.setlists.isEmpty) return _empty('Nenhum repertório', Icons.queue_music);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      itemCount: st.setlists.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final sl = st.setlists[i];
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            leading: const Icon(Icons.queue_music),
            title: Text(sl.name,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
            subtitle: Text('${sl.songIds.length} músicas'),
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'dup') st.duplicateSetlist(sl);
                if (v == 'del') {
                  _confirmDelete('Excluir "${sl.name}"?', () => st.deleteSetlist(sl.id));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'dup', child: Text('Duplicar')),
                PopupMenuItem(value: 'del', child: Text('Excluir')),
              ],
            ),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => SetlistPage(setlistId: sl.id))),
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
    st.upsertSong(s);
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => SongEditPage(songId: s.id)));
  }

  void _newSetlist(AppState st) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Novo repertório'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nome'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Criar')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      st.upsertSetlist(Setlist(id: ChordEngine.uid(), name: name.trim()));
    }
  }

  void _confirmDelete(String msg, VoidCallback onYes) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
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
