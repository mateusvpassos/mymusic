import 'package:flutter/material.dart';
import '../core/diff.dart';
import '../data/store.dart';
import '../models/song.dart';

/// Mostra o que muda de [antes] p/ [depois]: campos (tom, capo...) e a
/// cifra linha a linha (verde entrou, vermelho saiu).
class DiffView extends StatelessWidget {
  final Song antes, depois;
  const DiffView({super.key, required this.antes, required this.depois});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final campos = AppState.resumoMudancas(
      antes,
      depois,
    ).where((d) => !d.startsWith('Cifra alterada')).toList();
    final linhas = Diff.resumo(
      Diff.linhas(Diff.texto(antes), Diff.texto(depois)),
      contexto: 2,
    );
    final mono = TextStyle(
      fontFamily: 'ChordMono',
      fontSize: 13,
      height: 1.35,
      color: scheme.onSurface,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in campos)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(Icons.edit_note, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(child: Text(c)),
              ],
            ),
          ),
        if (campos.isNotEmpty) const SizedBox(height: 8),
        if (linhas.isEmpty)
          Text(
            'A cifra (letra e acordes) não muda.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final l in linhas)
                  if (l == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '⋯',
                        style: mono.copyWith(color: scheme.outline),
                      ),
                    )
                  else
                    Container(
                      color: l.tipo > 0
                          ? Colors.green.withValues(alpha: 0.18)
                          : l.tipo < 0
                          ? Colors.red.withValues(alpha: 0.18)
                          : null,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '${l.tipo > 0
                            ? '+'
                            : l.tipo < 0
                            ? '−'
                            : ' '} ${l.text}',
                        style: mono.copyWith(
                          decoration: l.tipo < 0
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: scheme.error,
                        ),
                        softWrap: true,
                      ),
                    ),
              ],
            ),
          ),
      ],
    );
  }
}

String fmtQuando(DateTime? d) {
  if (d == null) return 'agora';
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}
