import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../cloud/cloud_state.dart';
import '../core/chord_engine.dart';
import '../core/liturgia.dart';
import '../core/search.dart';
import '../data/store.dart';
import '../models/song.dart';
import 'song_edit_page.dart';
import 'song_view_page.dart';
import 'widgets/song_tile.dart';

/// Minhas músicas: a biblioteca (cópias próprias), com editar/duplicar/excluir.
class MinhasMusicasPage extends StatefulWidget {
  const MinhasMusicasPage({super.key});
  @override
  State<MinhasMusicasPage> createState() => _MinhasMusicasPageState();
}

class _MinhasMusicasPageState extends State<MinhasMusicasPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final cloud = context.watch<CloudState>();
    final list = SongSearch.run(st.songs, _query);
    if (_query.trim().isEmpty) {
      list.sort((x, y) => SongSearch.fold(x.song.title).compareTo(SongSearch.fold(y.song.title)));
    }
    final uso = UsoMusicas.calcula(st.setlists);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Minhas músicas'),
            Text(
              '${st.songs.length} na ${cloud.grupo?.nome ?? 'biblioteca'}',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Buscar (nome, artista ou trecho da letra)...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      _query.isEmpty ? 'Nenhuma música ainda' : 'Nada encontrado',
                      style: TextStyle(color: Theme.of(context).disabledColor),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _card(st, cloud, list[i].song,
                        trecho: list[i].snippet, uso: uso[list[i].song.id]),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Música'),
        onPressed: () {
          final s = Song(id: ChordEngine.uid(), title: 'Nova música');
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SongEditPage(songId: s.id, novo: s)),
          );
        },
      ),
    );
  }

  Widget _card(AppState st, CloudState cloud, Song s, {String? trecho, SongUse? uso}) {
    final meta = <String>[
      // no grupo: de quem é (as minhas não precisam dizer)
      if (cloud.ativa && s.dono.isNotEmpty && s.dono != cloud.eu) 'de ${cloud.nomeDe(s.dono)}',
      if (s.artist.isNotEmpty) s.artist,
      if (s.bpm > 0) '${s.bpm} BPM',
      if (uso != null) 'tocada ${UsoMusicas.quando(uso.ultima)} (${uso.vezes}x)',
    ].join('  •  ');
    return SongTile(
      title: s.title,
      keyLabel: s.key,
      trecho: trecho,
      meta: meta,
      tags: s.tags,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SongViewPage(songId: s.id)),
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
            _apagar(st, s);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'edit',
            child: Text(cloud.podeEditarSong(s) ? 'Editar' : 'Sugerir mudança'),
          ),
          const PopupMenuItem(value: 'dup', child: Text('Duplicar')),
          // no grupo só o dono apaga
          if (cloud.souDono(s.dono)) const PopupMenuItem(value: 'del', child: Text('Excluir')),
        ],
      ),
    );
  }

  void _apagar(AppState st, Song s) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Excluir "${s.title}"?'),
        content: const Text('Sai das suas músicas (o acervo geral não muda).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              st.deleteSong(s.id);
            },
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }
}
