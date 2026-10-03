import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/store.dart';
import 'acervo.dart';
import 'cloud_state.dart';
import 'diff_view.dart';

/// Sugestões: as que você decide e as que você mandou.
class SuggestionsPage extends StatelessWidget {
  const SuggestionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CloudState>();
    final a = context.watch<AcervoState>();
    int porData(Sugestao x, Sugestao y) =>
        (y.em ?? DateTime(0)).compareTo(x.em ?? DateTime(0));
    // grupo + acervo geral numa lista só
    final decidir = [...c.paraDecidir, ...a.paraDecidir]..sort(porData);
    final minhas = [...c.minhas, ...a.minhas]..sort(porData);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sugestões'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Para decidir (${decidir.length})'),
              Tab(text: 'Minhas (${minhas.length})'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _lista(context, decidir, 'Nenhuma sugestão esperando você.'),
            _lista(context, minhas, 'Você ainda não sugeriu nada.'),
          ],
        ),
      ),
    );
  }

  Widget _lista(BuildContext context, List<Sugestao> l, String vazio) {
    if (l.isEmpty) {
      return Center(
        child: Text(
          vazio,
          style: TextStyle(color: Theme.of(context).disabledColor),
        ),
      );
    }
    final c = context.read<CloudState>();
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: l.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final x = l[i];
        return Card(
          child: ListTile(
            leading: _StatusIcon(x.status),
            title: Text(
              '${x.acervo ? 'Acervo · ' : ''}${x.titulo}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              [
                if (x.por != c.eu)
                  'de ${x.porNome.isNotEmpty ? x.porNome : x.por}',
                fmtQuando(x.em),
                if (!x.pendente) _status(x),
                if (x.nota.isNotEmpty) '“${x.nota}”',
              ].join('  •  '),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SuggestionDetailPage(id: x.id)),
            ),
          ),
        );
      },
    );
  }
}

String _status(Sugestao x) => switch (x.status) {
  'aceita' =>
    'aceita${x.decididoPorNome.isNotEmpty ? ' por ${x.decididoPorNome}' : ''}',
  'recusada' =>
    'recusada${x.decididoPorNome.isNotEmpty ? ' por ${x.decididoPorNome}' : ''}'
        '${x.motivo.isNotEmpty ? ': ${x.motivo}' : ''}',
  'cancelada' => 'cancelada',
  _ => 'esperando',
};

class _StatusIcon extends StatelessWidget {
  final String status;
  const _StatusIcon(this.status);
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      'aceita' => const Icon(Icons.check_circle, color: Colors.green),
      'recusada' => Icon(Icons.cancel, color: scheme.error),
      'cancelada' => Icon(Icons.remove_circle_outline, color: scheme.outline),
      _ => Icon(Icons.hourglass_top, color: scheme.primary),
    };
  }
}

class SuggestionDetailPage extends StatelessWidget {
  final String id;
  const SuggestionDetailPage({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CloudState>();
    final st = context.watch<AppState>();
    final ac = context.watch<AcervoState>();
    final x = [...c.sugestoes, ...ac.sugestoes].where((s) => s.id == id).firstOrNull;
    if (x == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Sugestão não encontrada')),
      );
    }
    final atual = x.acervo ? ac.musicas[x.songId] : st.songById(x.songId);
    final podeDecidir = x.pendente &&
        x.por != c.eu &&
        atual != null &&
        (x.acervo ? ac.podeEditar(atual) : c.podeEditarSong(atual));
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(x.titulo)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Row(
            children: [
              _StatusIcon(x.status),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${x.porNome.isNotEmpty ? x.porNome : x.por} sugeriu em ${fmtQuando(x.em)}'
                  '${x.pendente ? '' : ' — ${_status(x)}'}',
                ),
              ),
            ],
          ),
          if (x.nota.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '“${x.nota}”',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
          if (atual != null && x.pendente && atual.versao > x.base) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'A música mudou depois desta sugestão (versão ${x.base} → ${atual.versao}). '
                'Aceitar troca pela versão sugerida inteira — confira as diferenças abaixo.',
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text('O que muda', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (atual == null)
            const Text('A música não existe mais.')
          else
            DiffView(antes: atual, depois: x.song),
        ],
      ),
      bottomNavigationBar: !podeDecidir && !(x.pendente && x.por == c.eu)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    if (podeDecidir) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.close),
                          label: const Text('Recusar'),
                          onPressed: () => _recusar(context, c, x),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.check),
                          label: const Text('Aceitar'),
                          onPressed: () async {
                            await (x.acervo ? ac.aceitar(x) : c.aceitar(x));
                            if (context.mounted) Navigator.pop(context);
                          },
                        ),
                      ),
                    ] else
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.undo),
                          label: const Text('Desistir da sugestão'),
                          onPressed: () async {
                            await (x.acervo ? ac.cancelar(x) : c.cancelar(x));
                            if (context.mounted) Navigator.pop(context);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _recusar(BuildContext context, CloudState c, Sugestao x) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Recusar sugestão'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Motivo (opcional)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Recusar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await (x.acervo
          ? context.read<AcervoState>().recusar(x, motivo: ctrl.text.trim())
          : c.recusar(x, motivo: ctrl.text.trim()));
      if (context.mounted) Navigator.pop(context);
    }
  }
}
