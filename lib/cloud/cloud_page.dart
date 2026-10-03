import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'acervo.dart';
import 'cloud_config.dart';
import 'cloud_state.dart';

/// Grupo compartilhado: entrar, convidar pessoas, quem pode editar o quê.
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
      appBar: AppBar(title: const Text('Grupo compartilhado')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (!c.disponivel)
            _card(
              context,
              icon: Icons.cloud_off,
              titulo: 'Nuvem ainda não configurada',
              children: const [
                Text(
                  'Falta criar o projeto no console do Firebase. Enquanto isso '
                  'o app continua sincronizando pelo Google Drive.',
                ),
              ],
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
              _confianca(context, c),
              _envio(context, c),
              _acervo(context),
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
        const Text(
          'Com a conta Google, as músicas ficam num grupo compartilhado: '
          'cada um vê tudo, quem criou é o dono e os outros mandam sugestões.',
        ),
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
    return _card(
      context,
      icon: Icons.account_circle,
      titulo: c.nome,
      trailing: TextButton(onPressed: c.sair, child: const Text('Sair')),
      children: [Text(c.eu)],
    );
  }

  Widget _semGrupo(BuildContext context, CloudState c) {
    return _card(
      context,
      icon: Icons.groups_outlined,
      titulo: 'Nenhum grupo ainda',
      children: [
        if (c.grupos.isNotEmpty) ...[
          for (final g in c.grupos)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.group),
              title: Text(g.nome),
              subtitle: Text('${g.membros.length} pessoa(s)'),
              onTap: () => c.escolherGrupo(g),
            ),
        ] else
          Text(
            'Para entrar no grupo de alguém, peça para te convidar com o '
            'e-mail ${c.eu}. Ou crie o seu grupo (banda, coral, ministério...):',
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _criarGrupo(context, c),
          icon: const Icon(Icons.add),
          label: const Text('Criar grupo'),
        ),
      ],
    );
  }

  Future<void> _criarGrupo(BuildContext context, CloudState c) async {
    final ctrl = TextEditingController();
    final nome = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Novo grupo'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Nome do grupo (ex.: banda, coral, ministério)',
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
    return _card(
      context,
      icon: Icons.groups,
      titulo: g.nome,
      trailing: c.grupos.length > 1
          ? PopupMenuButton<Grupo>(
              tooltip: 'Trocar de grupo',
              icon: const Icon(Icons.swap_horiz),
              onSelected: c.escolherGrupo,
              itemBuilder: (_) => [
                for (final x in c.grupos)
                  PopupMenuItem(value: x, child: Text(x.nome)),
              ],
            )
          : null,
      children: [
        Text(
          c.souDonoDoGrupo
              ? 'Você é o responsável pelo grupo.'
              : 'Responsável: ${c.nomeDe(g.dono)}',
        ),
        const SizedBox(height: 4),
        Text(
          c.carregou
              ? 'Sincronizado — as mudanças chegam na hora.'
              : 'Carregando...',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _pessoas(BuildContext context, CloudState c) {
    final g = c.grupo!;
    return _card(
      context,
      icon: Icons.people_outline,
      titulo: 'Pessoas (${g.membros.length})',
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
            title: Text(c.nomeDe(m)),
            subtitle: Text(m == g.dono ? '$m · responsável' : m),
            trailing: c.souDonoDoGrupo && m != g.dono
                ? IconButton(
                    icon: const Icon(Icons.person_remove_outlined),
                    tooltip: 'Tirar do grupo',
                    onPressed: () => c.remover(m),
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
                    hintText: 'E-mail Google de quem convidar',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  c.convidar(_convite.text);
                  _convite.clear();
                },
                child: const Text('Convidar'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'A pessoa entra no app com esse e-mail e já cai no grupo.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _confianca(BuildContext context, CloudState c) {
    final outros = c.grupo!.membros.where((m) => m != c.eu).toList();
    final atuais = c.confianca[c.eu] ?? const <String>[];
    return _card(
      context,
      icon: Icons.verified_user_outlined,
      titulo: 'Quem edita o que é seu sem pedir',
      children: [
        const Text(
          'Marcados podem mudar TODAS as suas músicas e repertórios direto. '
          'Os outros mandam sugestão e você aceita ou não. Dá p/ liberar '
          'também música por música (tela da música › Quem pode editar).',
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
                  label: Text(c.nomeDe(m)),
                  selected: atuais.contains(m),
                  onSelected: (v) => c.setConfianca(
                    v ? [...atuais, m] : atuais.where((x) => x != m).toList(),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _acervo(BuildContext context) {
    final a = context.watch<AcervoState>();
    if (!a.carregou) return const SizedBox.shrink();
    final falta = a.naoPublicadas;
    return _card(
      context,
      icon: Icons.public,
      titulo: 'Acervo geral',
      children: [
        Text(
          falta.isEmpty
              ? 'Todas as suas músicas estão no acervo. ${a.obras.length} músicas no acervo ao todo.'
              : '${falta.length} música(s) suas ainda não estão no acervo geral. '
                    'Publicando, todo mundo do app pode ver e puxar (você continua '
                    'dono; os outros sugerem). O grupo segue com as cópias dele.',
        ),
        if (falta.isNotEmpty) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            icon: const Icon(Icons.publish),
            label: Text('Publicar ${falta.length} no acervo'),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Publicar no acervo geral?'),
                  content: Text(
                    '${falta.length} música(s) ficam visíveis para todos que usam o app.',
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Publicar')),
                  ],
                ),
              );
              if (ok != true) return;
              for (final s in falta) {
                a.publicar(s);
              }
            },
          ),
        ],
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
          '$ns música(s) e $nr repertório(s) ainda não estão no grupo. '
          'Enviando, você vira o dono deles.',
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: c.enviarBiblioteca,
          icon: const Icon(Icons.upload),
          label: const Text('Enviar para o grupo'),
        ),
      ],
    );
  }
}
