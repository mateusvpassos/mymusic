import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/store.dart';
import '../models/audit.dart';

/// Histórico: o que mudou, quando e em quê.
class AuditPage extends StatefulWidget {
  const AuditPage({super.key});
  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  String _filtro = 'tudo'; // tudo | musica | repertorio | outros
  String _busca = '';

  static const _icones = {
    'criou': Icons.add_circle_outline,
    'editou': Icons.edit_outlined,
    'excluiu': Icons.delete_outline,
    'duplicou': Icons.copy_all_outlined,
    'importou': Icons.download_outlined,
    'exportou': Icons.ios_share,
    'sincronizou': Icons.cloud_done_outlined,
    'recebeu': Icons.wifi_tethering,
    'entrou': Icons.login,
    'saiu': Icons.logout,
  };

  Color _cor(ColorScheme s, String action) {
    switch (action) {
      case 'criou':
      case 'recebeu':
        return Colors.green.shade600;
      case 'excluiu':
        return s.error;
      case 'editou':
        return s.primary;
      default:
        return s.onSurfaceVariant;
    }
  }

  static String _quando(DateTime d) {
    final agora = DateTime.now();
    final dif = agora.difference(d);
    if (dif.inMinutes < 1) return 'agora';
    if (dif.inMinutes < 60) return '${dif.inMinutes} min atrás';
    if (dif.inHours < 24) return '${dif.inHours} h atrás';
    final hh = '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    if (dif.inDays < 7) return '${dif.inDays} d atrás  •  $hh';
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}  •  $hh';
  }

  static String _dia(DateTime d) {
    final hoje = DateTime.now();
    final s = DateTime(d.year, d.month, d.day);
    final h = DateTime(hoje.year, hoje.month, hoje.day);
    final dif = h.difference(s).inDays;
    if (dif == 0) return 'Hoje';
    if (dif == 1) return 'Ontem';
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  bool _passa(AuditEvent e) {
    final okFiltro = _filtro == 'tudo' ||
        (_filtro == 'outros'
            ? !const {'musica', 'repertorio', 'sessao'}.contains(e.entity)
            : e.entity == _filtro);
    if (!okFiltro) return false;
    if (_busca.isEmpty) return true;
    return e.title.toLowerCase().contains(_busca) ||
        e.action.contains(_busca) ||
        e.details.any((d) => d.toLowerCase().contains(_busca));
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final lista = st.audit.where(_passa).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Limpar histórico',
            onPressed: st.audit.isEmpty
                ? null
                : () => showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        content: const Text(
                            'Apagar todo o histórico? As músicas e repertórios não são afetados.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancelar')),
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(context);
                              st.clearAudit();
                            },
                            child: const Text('Apagar'),
                          ),
                        ],
                      ),
                    ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _busca = v.toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Buscar no histórico...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final f in const [
                  ['tudo', 'Tudo'],
                  ['musica', 'Músicas'],
                  ['repertorio', 'Repertórios'],
                  ['sessao', 'Ao vivo'],
                  ['outros', 'Outros'],
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(f[1]),
                      selected: _filtro == f[0],
                      onSelected: (_) => setState(() => _filtro = f[0]),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: lista.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history,
                            size: 64, color: Theme.of(context).disabledColor),
                        const SizedBox(height: 12),
                        Text(
                          st.audit.isEmpty
                              ? 'Nada registrado ainda'
                              : 'Nada encontrado',
                          style:
                              TextStyle(color: Theme.of(context).disabledColor),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: lista.length,
                    itemBuilder: (_, i) {
                      final e = lista[i];
                      final novoDia = i == 0 ||
                          _dia(lista[i - 1].at) != _dia(e.at);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (novoDia)
                            Padding(
                              padding: EdgeInsets.fromLTRB(4, i == 0 ? 0 : 16, 4, 6),
                              child: Text(
                                _dia(e.at),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  letterSpacing: 0.6,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(_icones[e.action] ?? Icons.circle_outlined,
                                      size: 20, color: _cor(scheme, e.action)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${e.action[0].toUpperCase()}${e.action.substring(1)} ${_rotulo(e.entity)} "${e.title}"',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(_quando(e.at),
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: scheme.onSurfaceVariant)),
                                        if (e.details.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          for (final d in e.details)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 2),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text('•  ',
                                                      style: TextStyle(
                                                          color: scheme
                                                              .onSurfaceVariant)),
                                                  Expanded(
                                                    child: Text(d,
                                                        style: TextStyle(
                                                            fontSize: 13,
                                                            color: scheme
                                                                .onSurfaceVariant)),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static String _rotulo(String entity) {
    switch (entity) {
      case 'musica':
        return 'a música';
      case 'repertorio':
        return 'o repertório';
      case 'backup':
        return 'o backup';
      case 'config':
        return 'a configuração';
      case 'sessao':
        return 'na sessão:';
      default:
        return entity;
    }
  }
}
