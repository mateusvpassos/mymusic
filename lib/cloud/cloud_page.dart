import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'cloud_config.dart';
import 'cloud_state.dart';

/// Conta e compartilhamento: quem você é, de quem é a biblioteca em uso,
/// quem tem acesso a ela e quem pode editar direto.
class CloudPage extends StatefulWidget {
  const CloudPage({super.key});
  @override
  State<CloudPage> createState() => _CloudPageState();
}

class _CloudPageState extends State<CloudPage> {
  final _convite = TextEditingController();
  final _emailTeste = TextEditingController();
  final _nomeTeste = TextEditingController();

  @override
  void dispose() {
    _convite.dispose();
    _emailTeste.dispose();
    _nomeTeste.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CloudState>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Conta e compartilhamento')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (!c.disponivel)
            _card(
              context,
              icon: Icons.cloud_off,
              titulo: 'Nuvem ainda não configurada',
              children: const [Text('Falta configurar o Firebase.')],
            )
          else if (c.user == null)
            _entrar(context, c)
          else ...[
            _conta(context, c),
            if (c.grupo == null)
              _semGrupo(context, c)
            else ...[
              _grupo(context, c),
              _pessoas(context, c),
              if (c.souDonoDoGrupo) _confianca(context, c),
              _envio(context, c),
              _acervo(context),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _criarGrupo(context, c),
                  icon: const Icon(Icons.add),
                  label: const Text('Criar outra biblioteca separada (ex.: de um coral)'),
                ),
              ),
            ],
          ],
          if (c.erro != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(c.erro!, style: TextStyle(color: scheme.error)),
            ),
        ],
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required IconData icon,
    required String titulo,
    required List<Widget> children,
    Widget? trailing,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _entrar(BuildContext context, CloudState c) {
    return _card(
      context,
      icon: Icons.login,
      titulo: 'Entrar',
      children: [
        const Text('Entre com a conta Google p/ ver o acervo e as suas músicas.'),
        const SizedBox(height: 12),
        if (CloudConfig.emulador) ...[
          TextField(
            controller: _emailTeste,
            decoration: const InputDecoration(hintText: 'E-mail (teste)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nomeTeste,
            decoration: const InputDecoration(hintText: 'Nome (teste)'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () =>
                c.entrarTeste(_emailTeste.text.trim(), _nomeTeste.text.trim()),
            child: const Text('Entrar (emulador)'),
          ),
        ] else
          FilledButton.icon(
            onPressed: c.entrar,
            icon: const Icon(Icons.account_circle),
            label: const Text('Entrar com Google'),
          ),
      ],
    );
  }

  Widget _conta(BuildContext context, CloudState c) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        leading: CircleAvatar(
          radius: 22,
          child: Text(c.nome.isEmpty ? '?' : c.nome[0].toUpperCase(),
              style: const TextStyle(fontSize: 20)),
        ),
        title: Text(c.nome, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(c.eu),
        trailing: TextButton(onPressed: c.sair, child: const Text('Sair')),
      ),
    );
  }

  Widget _semGrupo(BuildContext context, CloudState c) {
    // a biblioteca pessoal é criada sozinha; aqui só se tiver várias p/ escolher
    if (c.grupos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Preparando a sua biblioteca...'),
      );
    }
    return _card(
      context,
      icon: Icons.library_music_outlined,
      titulo: 'Qual biblioteca abrir?',
      children: [
        for (final g in c.grupos)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.library_music),
            title: Text(g.dono == c.eu ? 'Minha biblioteca' : g.nome),
            subtitle: Text('${g.membros.length} pessoa(s)'),
            onTap: () => c.escolherGrupo(g),
          ),
      ],
    );
  }

  Future<void> _criarGrupo(BuildContext context, CloudState c) async {
    final ctrl = TextEditingController();
    final nome = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nova biblioteca'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Nome (ex.: Coral da paróquia)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Criar'),
          ),
        ],
      ),
    );
    if (nome != null && nome.isNotEmpty) await c.criarGrupo(nome);
  }

  Widget _grupo(BuildContext context, CloudState c) {
    final g = c.grupo!;
    final cinza = Theme.of(context).colorScheme.onSurfaceVariant;
    return _card(
      context,
      icon: Icons.library_music_outlined,
      titulo: c.souDonoDoGrupo ? 'Sua biblioteca' : 'Biblioteca de ${c.nomeDe(g.dono)}',
      children: [
        Text(
          c.souDonoDoGrupo
              ? 'As suas músicas e os seus repertórios ficam salvos aqui, na nuvem. '
                    'Quem você convidar vê tudo, toca junto e pode sugerir mudanças '
                    '— você aceita ou não (ícone de caixa de entrada na tela inicial).'
              : '${c.nomeDe(g.dono)} te convidou. Você vê e toca tudo; o que for '
                    'dos outros você muda mandando sugestão, a não ser que te '
                    'liberem p/ editar direto.',
        ),
        if (c.grupos.length > 1) ...[
          const SizedBox(height: 10),
          Text('Você tem acesso a ${c.grupos.length} bibliotecas:',
              style: TextStyle(color: cinza)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final x in c.grupos)
                ChoiceChip(
                  label: Text(x.dono == c.eu ? 'Minha' : x.nome),
                  selected: x.id == g.id,
                  onSelected: (_) => c.escolherGrupo(x),
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(c.carregou ? Icons.cloud_done_outlined : Icons.cloud_sync_outlined,
                size: 18, color: cinza),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                c.carregou
                    ? 'Tudo salvo — as mudanças chegam na hora p/ todos.'
                    : 'Carregando...',
                style: TextStyle(color: cinza, fontSize: 13),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _pessoas(BuildContext context, CloudState c) {
    final g = c.grupo!;
    return _card(
      context,
      icon: Icons.people_outline,
      titulo: 'Quem tem acesso (${g.membros.length})',
      children: [
        for (final m in g.membros)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 16,
              child: Text(
                c.nomeDe(m).isEmpty ? '?' : c.nomeDe(m)[0].toUpperCase(),
              ),
            ),
            title: Text('${c.nomeDe(m)}${m == c.eu ? ' (você)' : ''}'),
            subtitle: Text(m == g.dono ? '$m · dono da biblioteca' : m),
            trailing: c.souDonoDoGrupo && m != g.dono
                ? IconButton(
                    icon: const Icon(Icons.person_remove_outlined),
                    tooltip: 'Tirar o acesso',
                    onPressed: () => _tirar(context, c, m),
                  )
                : null,
          ),
        if (c.souDonoDoGrupo) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _convite,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'E-mail Google da pessoa',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final e = _convite.text.trim().toLowerCase();
                  if (e.isNotEmpty) c.convidar(e);
                  _convite.clear();
                },
                child: const Text('Convidar'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'A pessoa instala o app, entra com esse e-mail e já vê a sua biblioteca.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _tirar(BuildContext context, CloudState c, String m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tirar o acesso?'),
        content: Text('${c.nomeDe(m)} deixa de ver a sua biblioteca.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tirar')),
        ],
      ),
    );
    if (ok == true) c.remover(m);
  }

  Widget _confianca(BuildContext context, CloudState c) {
    final outros = c.grupo!.membros.where((m) => m != c.eu).toList();
    final atuais = c.confianca[c.eu] ?? const <String>[];
    return _card(
      context,
      icon: Icons.edit_note,
      titulo: 'Quem pode editar direto',
      children: [
        const Text(
          'Normalmente só você muda as suas músicas; os outros mandam sugestão. '
          'Marque quem pode mudar TUDO direto, sem pedir:',
        ),
        const SizedBox(height: 8),
        if (outros.isEmpty)
          const Text('Convide alguém primeiro.')
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in outros)
                FilterChip(
                  avatar: atuais.contains(m) ? null : const Icon(Icons.add, size: 16),
                  label: Text(c.nomeDe(m)),
                  selected: atuais.contains(m),
                  onSelected: (v) => c.setConfianca(
                    v ? [...atuais, m] : atuais.where((x) => x != m).toList(),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 8),
        Text(
          'Dá p/ liberar também só uma música ou um repertório (na tela dele › '
          'Dono e quem pode editar).',
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _acervo(BuildContext context) {
    return _card(
      context,
      icon: Icons.public,
      titulo: 'Acervo geral',
      children: const [
        Text(
          'É a aba Músicas da tela inicial: todas as músicas de quem usa o app. '
          'As suas entram lá sozinhas (continuam suas; os outros só sugerem). '
          'Ao tocar ou pôr no repertório uma do acervo, ela vem p/ as suas '
          'músicas como cópia — dá p/ mudar o tom e as anotações sem mexer na original.',
        ),
      ],
    );
  }

  Widget _envio(BuildContext context, CloudState c) {
    if (!c.carregou) return const SizedBox.shrink();
    final ns = c.songsSoAqui, nr = c.setsSoAqui;
    if (ns == 0 && nr == 0) return const SizedBox.shrink();
    return _card(
      context,
      icon: Icons.cloud_upload_outlined,
      titulo: 'Só neste aparelho',
      children: [
        Text(
          '$ns música(s) e $nr repertório(s) ainda não estão na nuvem. '
          'Enviando, você vira o dono deles.',
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: c.enviarBiblioteca,
          icon: const Icon(Icons.upload),
          label: const Text('Enviar p/ a nuvem'),
        ),
      ],
    );
  }
}
