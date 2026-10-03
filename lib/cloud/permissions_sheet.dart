import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'cloud_state.dart';

/// Dono e quem mais pode editar (música ou repertório). Só o dono muda.
Future<void> showPermissions(
  BuildContext context, {
  required String titulo,
  required String dono,
  required List<String> editores,
  required Future<void> Function(List<String>) salvar,
}) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (_) => _Permissoes(
      titulo: titulo,
      dono: dono,
      editores: editores,
      salvar: salvar,
    ),
  );
}

class _Permissoes extends StatefulWidget {
  final String titulo, dono;
  final List<String> editores;
  final Future<void> Function(List<String>) salvar;
  const _Permissoes({
    required this.titulo,
    required this.dono,
    required this.editores,
    required this.salvar,
  });
  @override
  State<_Permissoes> createState() => _PermissoesState();
}

class _PermissoesState extends State<_Permissoes> {
  late final List<String> _ed = List.of(widget.editores);

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CloudState>();
    final souDono = c.souDono(widget.dono);
    final outros = (c.grupo?.membros ?? const <String>[])
        .where((m) => m != widget.dono)
        .toList();
    final confiados = c.confianca[widget.dono] ?? const <String>[];
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.titulo,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text('Dono: ${c.nomeDe(widget.dono)}'),
            const SizedBox(height: 12),
            Text(
              souDono
                  ? 'Quem mais pode editar direto (os outros mandam sugestão):'
                  : 'Podem editar direto:',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in outros)
                  FilterChip(
                    label: Text(c.nomeDe(m)),
                    // liberado p/ tudo do dono: marcado e travado
                    selected: _ed.contains(m) || confiados.contains(m),
                    tooltip: confiados.contains(m)
                        ? 'Liberado para tudo de ${c.nomeDe(widget.dono)}'
                        : null,
                    onSelected: !souDono || confiados.contains(m)
                        ? null
                        : (v) => setState(() => v ? _ed.add(m) : _ed.remove(m)),
                  ),
              ],
            ),
            if (souDono) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () async {
                    await widget.salvar(_ed);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Salvar'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
