import 'package:flutter/material.dart';

/// Cartão de música das listas (acervo e minhas músicas): tom num quadrado
/// colorido, título, trecho achado na busca, uma linha de detalhes e tags.
class SongTile extends StatelessWidget {
  final String title;
  final String keyLabel;
  final String? trecho;
  final String meta;
  final List<String> tags;
  final Widget? trailing;
  final VoidCallback onTap;
  const SongTile({
    super.key,
    required this.title,
    required this.keyLabel,
    required this.onTap,
    this.trecho,
    this.meta = '',
    this.tags = const [],
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        subtitle: (meta.isEmpty && tags.isEmpty && trecho == null)
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // achou pela letra: mostra o trecho
                  if (trecho != null)
                    Text(
                      '“$trecho”',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.primary, fontStyle: FontStyle.italic),
                    ),
                  if (meta.isNotEmpty)
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  if (tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: [
                          for (final t in tags.take(4))
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(t,
                                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [scheme.primary, scheme.tertiary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(13),
          ),
          alignment: Alignment.center,
          child: Text(
            keyLabel,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}
