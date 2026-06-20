import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/image_export.dart';
import '../core/pdf_export.dart';
import '../core/text_export.dart';
import '../data/store.dart';
import '../models/song.dart';
import 'song_view_page.dart';

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

Color _strong(int seed) {
  final hsl = HSLColor.fromColor(Color(seed));
  return hsl
      .withSaturation((hsl.saturation * 1.25).clamp(0.85, 1.0))
      .withLightness(0.42)
      .toColor();
}

class SetlistPage extends StatelessWidget {
  final String setlistId;
  const SetlistPage({super.key, required this.setlistId});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final sl = st.setlists.firstWhere((s) => s.id == setlistId,
        orElse: () => Setlist(id: '', name: '—'));
    final songs = sl.songIds.map((id) => st.songById(id)).whereType<Song>().toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(sl.name),
            if (sl.date != null)
              Text(_fmtDate(sl.date!),
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.event),
            tooltip: 'Data do evento',
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: sl.date ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (d != null) {
                sl.date = d;
                st.upsertSetlist(sl);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.play_circle_fill),
            tooltip: 'Iniciar',
            onPressed: songs.isEmpty
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SongViewPage(
                          songId: songs.first.id,
                          setlistId: sl.id,
                          setlistSongIds: List.of(sl.songIds),
                        ),
                      ),
                    ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Exportar',
            enabled: songs.isNotEmpty,
            onSelected: (v) {
              if (v == 'img') {
                ImageExport.shareSetlist(
                  sl.name,
                  songs.map((s) => s.title).toList(),
                  chordColor: _strong(st.settings.seedColor),
                );
              } else if (v == 'txt') {
                TextExport.shareSetlistLyrics(sl.name, songs);
              } else if (v == 'pdf') {
                PdfExport.printSetlist(sl.name, songs,
                    colorArgb: _strong(st.settings.seedColor).toARGB32());
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('PDF (todas as cifras)')),
              PopupMenuItem(value: 'img', child: Text('Imagem da lista')),
              PopupMenuItem(value: 'txt', child: Text('Letras (TXT) — cantores')),
            ],
          ),
        ],
      ),
      body: songs.isEmpty
          ? Center(
              child: Text('Vazio — adicione músicas',
                  style: TextStyle(color: Theme.of(context).disabledColor)),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
              itemCount: songs.length,
              onReorder: (a, b) {
                if (b > a) b--;
                final id = sl.songIds.removeAt(a);
                sl.songIds.insert(b, id);
                st.upsertSetlist(sl);
              },
              itemBuilder: (_, i) {
                final s = songs[i];
                return Card(
                  key: ValueKey(s.id),
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text(s.title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${s.key}${s.artist.isNotEmpty ? '  •  ${s.artist}' : ''}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () {
                            sl.songIds.remove(s.id);
                            st.upsertSetlist(sl);
                          },
                        ),
                        const Icon(Icons.drag_handle),
                      ],
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SongViewPage(
                          songId: s.id,
                          setlistId: sl.id,
                          setlistSongIds: List.of(sl.songIds),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addSongs(context, st, sl),
        icon: const Icon(Icons.add),
        label: const Text('Músicas'),
      ),
    );
  }

  void _addSongs(BuildContext context, AppState st, Setlist sl) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            builder: (_, controller) => ListView(
              controller: controller,
              children: [
                for (final s in st.songs)
                  CheckboxListTile(
                    value: sl.songIds.contains(s.id),
                    title: Text(s.title),
                    subtitle: Text(s.key),
                    onChanged: (v) {
                      if (v == true) {
                        if (!sl.songIds.contains(s.id)) sl.songIds.add(s.id);
                      } else {
                        sl.songIds.remove(s.id);
                      }
                      st.upsertSetlist(sl);
                      setSheet(() {});
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
