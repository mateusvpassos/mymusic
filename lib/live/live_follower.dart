import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  @override
  void initState() {
    super.initState();
    _sub = context.read<LiveSession>().navStream.listen(_onNav);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
