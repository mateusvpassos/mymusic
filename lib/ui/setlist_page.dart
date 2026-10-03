import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/chord_engine.dart';
import '../core/docx_export.dart';
import '../core/image_export.dart';
import '../core/liturgia.dart';
import '../core/pdf_export.dart';
import '../core/search.dart';
import '../core/text_export.dart';
import '../data/store.dart';
import '../models/song.dart';
import 'song_view_page.dart';

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Cifras já no tom escolhido no repertório — é isso que tem que sair na
/// exportação, não o tom original da música.
/// Com o momento da Missa na frente do título ("Entrada · ...").
List<Song> _noTomDoRepertorio(Setlist sl, List<Song> songs) => songs.map((s) {
  final steps = sl.transpose[s.id] ?? 0;
  final c = steps == 0 ? s.copy() : ChordEngine.transposeSong(s, steps);
  final m = sl.moments[s.id];
  if (m != null) c.title = '$m · ${c.title}';
  return c;
}).toList();

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
    final sl = st.setlists.firstWhere(
      (s) => s.id == setlistId,
      orElse: () => Setlist(id: '', name: '—'),
    );
    final songs = sl.songIds
        .map((id) => st.songById(id))
        .whereType<Song>()
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(sl.name),
            if (sl.date != null)
              Text(
                _fmtDate(sl.date!),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
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
          if (sl.moments.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.sort),
              tooltip: 'Ordenar pela ordem da Missa',
              onPressed: () {
                // estável: dentro do mesmo momento mantém a ordem atual
                final ids = List.of(sl.songIds);
                final pos = {for (var i = 0; i < ids.length; i++) ids[i]: i};
                ids.sort((a, b) {
                  final c = Liturgia.ordem(
                    sl.moments[a],
                  ).compareTo(Liturgia.ordem(sl.moments[b]));
                  return c != 0 ? c : pos[a]!.compareTo(pos[b]!);
                });
                sl.songIds = ids;
                st.upsertSetlist(sl);
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
              final cor = _strong(st.settings.seedColor);
              final cifras = _noTomDoRepertorio(sl, songs);
              if (v == 'img') {
                ImageExport.shareSetlist(
                  sl.name,
                  cifras.map((s) => s.title).toList(),
                  chordColor: cor,
                );
              } else if (v == 'txt') {
                TextExport.shareSetlistLyrics(sl.name, cifras);
              } else if (v == 'pdf') {
                PdfExport.printSetlist(
                  sl.name,
                  cifras,
                  colorArgb: cor.toARGB32(),
                );
              } else if (v == 'docx') {
                DocxExport.shareSetlist(sl.name, cifras, chordColor: cor);
              }
              st.logEvent(
                'exportou',
                'repertorio',
                sl.name,
                details: [
                  'Formato: ${v.toUpperCase()}',
                  '${songs.length} música(s)',
                ],
              );
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('PDF (todas as cifras)')),
              PopupMenuItem(value: 'docx', child: Text('Word (.docx)')),
              PopupMenuItem(value: 'img', child: Text('Imagem da lista')),
              PopupMenuItem(
                value: 'txt',
                child: Text('Letras (TXT) — cantores'),
              ),
            ],
          ),
        ],
      ),
      body: songs.isEmpty
          ? Center(
              child: Text(
                'Vazio — adicione músicas',
                style: TextStyle(color: Theme.of(context).disabledColor),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
              itemCount: songs.length,
              // índices são da lista VISÍVEL; songIds pode ter música que não
              // existe mais aqui (excluída em outro aparelho) — por isso
              // reordena os visíveis e deixa os órfãos no fim
              onReorderItem: (a, b) {
                final ids = songs.map((s) => s.id).toList();
                ids.insert(b, ids.removeAt(a));
                sl.songIds = [
                  ...ids,
                  ...sl.songIds.where((x) => !ids.contains(x)),
                ];
                st.upsertSetlist(sl);
              },
              itemBuilder: (_, i) {
                final s = songs[i];
                final momento = sl.moments[s.id];
                return Card(
                  key: ValueKey(s.id),
                  margin: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 4,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text.rich(
                      TextSpan(
                        children: [
                          if (momento != null)
                            TextSpan(
                              text: '${momento.toUpperCase()}   ',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          TextSpan(text: s.title),
                        ],
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${s.key}${s.artist.isNotEmpty ? '  •  ${s.artist}' : ''}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            momento == null ? Icons.label_outline : Icons.label,
                          ),
                          tooltip: 'Momento da Missa',
                          onPressed: () => _escolherMomento(context, st, sl, s),
                        ),
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

  Future<void> _escolherMomento(
    BuildContext context,
    AppState st,
    Setlist sl,
    Song s,
  ) async {
    final atual = sl.moments[s.id];
    final r = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in Liturgia.momentos)
                    ChoiceChip(
                      label: Text(m),
                      selected: m == atual,
                      // momentos marcados na própria música em destaque
                      avatar: s.momentos.contains(m) && m != atual
                          ? const Icon(Icons.star, size: 16)
                          : null,
                      onSelected: (_) => Navigator.pop(context, m),
                    ),
                  if (atual != null)
                    ActionChip(
                      avatar: const Icon(Icons.close, size: 16),
                      label: const Text('Sem momento'),
                      onPressed: () => Navigator.pop(context, ''),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (r == null) return;
    if (r.isEmpty) {
      sl.moments.remove(s.id);
    } else {
      sl.moments[s.id] = r;
    }
    st.upsertSetlist(sl);
  }

  void _addSongs(BuildContext context, AppState st, Setlist sl) {
    // data da Missa (ou hoje) define o tempo litúrgico das sugestões
    final data = sl.date ?? DateTime.now();
    final tempos = Liturgia.temposDe(data);
    // uso ANTES desta Missa, sem contar o próprio repertório
    final uso = UsoMusicas.calcula(st.setlists, ate: data, exceto: sl.id);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        var busca = '';
        String? momento; // filtro
        var soTempo = true;
        return StatefulBuilder(
          builder: (context, setSheet) {
            final scheme = Theme.of(context).colorScheme;
            bool especifica(Song s) => s.tempos.any(tempos.contains);
            bool doTempo(Song s) => s.tempos.isEmpty || especifica(s);
            var achadas = SongSearch.run(st.songs, busca);
            if (momento != null) {
              achadas = achadas
                  .where((h) => h.song.momentos.contains(momento))
                  .toList();
            }
            if (busca.trim().isEmpty) {
              if (soTempo) {
                achadas = achadas.where((h) => doTempo(h.song)).toList();
              }
              // primeiro as do tempo; depois as que faz mais tempo que não toca
              DateTime quando(Song s) =>
                  uso[s.id]?.ultima ?? DateTime.utc(1900);
              achadas.sort((a, b) {
                final ea = especifica(a.song) ? 0 : 1;
                final eb = especifica(b.song) ? 0 : 1;
                if (ea != eb) return ea.compareTo(eb);
                return quando(a.song).compareTo(quando(b.song));
              });
            }
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.85,
              builder: (_, controller) => ListView(
                controller: controller,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Buscar por nome ou trecho da letra...',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (v) => setSheet(() => busca = v),
                    ),
                  ),
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        FilterChip(
                          avatar: const Icon(Icons.church_outlined, size: 16),
                          label: Text(tempos.first),
                          tooltip:
                              'Só cantos de ${tempos.first} (${_fmtDate(data)}) '
                              'ou sem tempo marcado',
                          selected: soTempo,
                          onSelected: (v) => setSheet(() => soTempo = v),
                        ),
                        const SizedBox(width: 12),
                        for (final m in Liturgia.momentos) ...[
                          ChoiceChip(
                            label: Text(m),
                            selected: momento == m,
                            onSelected: (v) =>
                                setSheet(() => momento = v ? m : null),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ],
                    ),
                  ),
                  if (achadas.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        momento != null
                            ? 'Nenhum canto marcado p/ "$momento"'
                                  '${soTempo ? ' em ${tempos.first}' : ''}.\n'
                                  'Marque na edição da música (tempo litúrgico '
                                  'e momento da Missa).'
                            : 'Nenhuma música encontrada.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  for (final h in achadas)
                    CheckboxListTile(
                      value: sl.songIds.contains(h.song.id),
                      title: Text(h.song.title),
                      subtitle: Text(
                        [
                          h.song.key,
                          if (uso[h.song.id] case final u?)
                            'tocada ${UsoMusicas.quando(u.ultima, hoje: data)} (${u.vezes}x)'
                          else
                            'nunca tocada',
                          if (h.snippet != null) '“${h.snippet}”',
                        ].join('  •  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      secondary: especifica(h.song)
                          ? Icon(Icons.church, size: 18, color: scheme.primary)
                          : const SizedBox(width: 18), // alinha os títulos
                      onChanged: (v) {
                        final id = h.song.id;
                        if (v == true) {
                          if (!sl.songIds.contains(id)) sl.songIds.add(id);
                          // momento: o do filtro, ou o único da música
                          final m =
                              momento ??
                              (h.song.momentos.length == 1
                                  ? h.song.momentos.first
                                  : null);
                          if (m != null) sl.moments[id] = m;
                        } else {
                          sl.songIds.remove(id);
                          sl.moments.remove(id);
                        }
                        st.upsertSetlist(sl);
                        setSheet(() {});
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
