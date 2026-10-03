import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../data/store.dart';
import '../ui/song_view_page.dart';
import 'live_session.dart';

/// Fica em volta da tela inicial: quando quem conduz abre uma música e este
/// aparelho (seguindo) não está em nenhuma tela de música, abre ela sozinho.
/// Se já houver uma aberta, ela mesma troca de música.
class LiveFollower extends StatefulWidget {
  final Widget child;
  const LiveFollower({super.key, required this.child});
  @override
  State<LiveFollower> createState() => _LiveFollowerState();
}

class _LiveFollowerState extends State<LiveFollower> {
  StreamSubscription<LiveNav>? _sub;
  late final LiveSession _live = context.read<LiveSession>();
  bool _acesa = false;

  @override
  void initState() {
    super.initState();
    _sub = _live.navStream.listen(_onNav);
    _live.addListener(_tela);
  }

  // Em sessão a tela não apaga: com a tela apagada o app pausa e quem segue
  // deixa de acompanhar. Fora da sessão, só a tela da música segura acesa.
  void _tela() {
    final querAcesa = _live.active;
    if (querAcesa == _acesa) return;
    _acesa = querAcesa;
    if (querAcesa) {
      WakelockPlus.enable();
    } else if (SongViewPage.openCount == 0) {
      WakelockPlus.disable();
    }
  }

  void _onNav(LiveNav n) {
    if (!mounted || SongViewPage.openCount > 0) return;
    final st = context.read<AppState>();
    if (st.songById(n.songId) == null) return;
    final sl = n.setlistId == null ? null : st.setlistById(n.setlistId!);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SongViewPage(
        songId: n.songId,
        setlistId: sl?.id,
        setlistSongIds: sl == null ? null : List.of(sl.songIds),
      ),
    ));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _live.removeListener(_tela);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
