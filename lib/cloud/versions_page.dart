import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/store.dart';
import '../models/song.dart';
import '../ui/widgets/chord_chart.dart';
import 'acervo.dart';
import 'cloud_state.dart';
import 'diff_view.dart';

/// Histórico de revisões da música (do grupo ou do acervo): cada gravação,
/// quem fez e o que mudou; dá p/ voltar a qualquer uma.
class VersionsPage extends StatefulWidget {
  final String songId;
  final bool acervo;
  const VersionsPage({super.key, required this.songId, this.acervo = false});
  @override
  State<VersionsPage> createState() => _VersionsPageState();
}

/// O que muda entre música do grupo e versão do acervo.
class _Fonte {
  final Song? song;
  final String Function(String) nomeDe;
  final bool pode;
  final Future<List<Versao>> Function() revisoes;
  final void Function(Song atual, Versao v) restaurar;
  final Future<void> Function(Song proposta, String nota) sugerir;
  _Fonte(this.song, this.nomeDe, this.pode, this.revisoes, this.restaurar, this.sugerir);

  factory _Fonte.de(BuildContext context, String id, bool acervo) {
    final c = context.watch<CloudState>();
    if (acervo) {
      final a = context.watch<AcervoState>();
      final s = a.musicas[id];
      return _Fonte(s, a.nomeDe, s != null && a.podeEditar(s), () => a.revisoes(id),
          a.restaurar, (p, n) => a.sugerir(p, nota: n));
    }
    final s = context.watch<AppState>().songById(id);
    return _Fonte(s, c.nomeDe, s != null && c.podeEditarSong(s), () => c.versoes(id),
        c.restaurar, (p, n) => c.sugerir(p, nota: n));
  }
}

class _VersionsPageState extends State<VersionsPage> {
  Future<List<Versao>>? _f;

  @override
  Widget build(BuildContext context) {
    final f = _Fonte.de(context, widget.songId, widget.acervo);
    _f ??= f.revisoes();
    final s = f.song;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(s == null ? 'Histórico' : 'Histórico — ${s.title}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _f = f.revisoes()),
          ),
        ],
      ),
      body: FutureBuilder<List<Versao>>(
        future: _f,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final l = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (s != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    [
                      if (widget.acervo) 'Acervo — ${AcervoState.rotulo(s)}',
                      'Dono: ${f.nomeDe(s.dono)}',
                      if (s.editores.isNotEmpty)
                        'podem editar: ${s.editores.map(f.nomeDe).join(', ')}',
                    ].join('  •  '),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              if (l.isEmpty) const Text('Sem revisões guardadas ainda.'),
              for (final v in l)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: v.n == s?.versao ? scheme.primary : null,
                      foregroundColor: v.n == s?.versao ? scheme.onPrimary : null,
                      child: Text('${v.n}'),
                    ),
                    title: Text(
                      '${v.porNome.isNotEmpty ? v.porNome : v.por} ${v.acao}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      [
                        fmtQuando(v.em),
                        if (v.n == s?.versao) 'revisão atual',
                        ...v.resumo,
                      ].join('\n'),
                    ),
                    isThreeLine: v.resumo.isNotEmpty,
                    onTap: s == null
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _RevisaoPage(
                                  v: v,
                                  songId: s.id,
                                  acervo: widget.acervo,
                                ),
                              ),
                            ).then((_) => setState(() => _f = f.revisoes())),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RevisaoPage extends StatefulWidget {
  final Versao v;
  final String songId;
  final bool acervo;
  const _RevisaoPage({required this.v, required this.songId, required this.acervo});
  @override
  State<_RevisaoPage> createState() => _RevisaoPageState();
}

class _RevisaoPageState extends State<_RevisaoPage> {
  bool _diff = true;

  @override
  Widget build(BuildContext context) {
    final f = _Fonte.de(context, widget.songId, widget.acervo);
    final atual = f.song;
    final v = widget.v;
    final scheme = Theme.of(context).colorScheme;
    final pode = f.pode;
    final eAtual = atual?.versao == v.n;
    return Scaffold(
      appBar: AppBar(
        title: Text('Revisão ${v.n}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Diferença p/ atual')),
                ButtonSegment(value: false, label: Text('Cifra desta revisão')),
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
                ? const Text('Esta é a revisão atual.')
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
                  label: Text(pode ? 'Voltar para esta revisão' : 'Sugerir voltar para esta revisão'),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text(pode ? 'Voltar para a revisão ${v.n}?' : 'Sugerir a revisão ${v.n}?'),
                        content: Text(
                          pode
                              ? 'A música fica igual a esta revisão. A atual continua no '
                                  'histórico — dá para voltar de novo.'
                              : 'O dono (${f.nomeDe(atual.dono)}) decide se aceita.',
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar')),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    if (pode) {
                      f.restaurar(atual, v);
                    } else {
                      await f.sugerir(v.song.copy()..id = atual.id, 'Voltar para a revisão ${v.n}');
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ),
            ),
    );
  }
}
