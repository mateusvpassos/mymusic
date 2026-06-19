import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../core/chord_engine.dart';
import '../core/chord_shapes.dart';
import '../core/image_export.dart';
import '../core/pdf_export.dart';
import '../core/pedal.dart';
import '../data/store.dart';
import '../models/song.dart';
import 'song_edit_page.dart';
import 'widgets/chord_chart.dart';

class SongViewPage extends StatefulWidget {
  final String songId;
  final String? setlistId;
  final List<String>? setlistSongIds;
  const SongViewPage({
    super.key,
    required this.songId,
    this.setlistId,
    this.setlistSongIds,
  });
  @override
  State<SongViewPage> createState() => _SongViewPageState();
}

class _SongViewPageState extends State<SongViewPage> with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  final _focus = FocusNode();
  late String _songId;
  int _transpose = 0;
  bool _autoScroll = false;
  bool _full = false;
  int _dir = 1; // direção da última troca (1 = próxima, -1 = anterior)
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  // navegação: setlist (se veio de um repertório) OU toda a biblioteca
  List<String> get _list =>
      widget.setlistSongIds ?? context.read<AppState>().songs.map((s) => s.id).toList();
  int get _idx => _list.indexOf(_songId);
  bool get _hasNav => _list.length > 1;

  @override
  void initState() {
    super.initState();
    _songId = widget.songId;
    _ticker = createTicker(_onTick);
    WakelockPlus.enable();
    _loadTranspose();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _loadTranspose() {
    if (widget.setlistId == null) return;
    final st = context.read<AppState>();
    final sl = st.setlists.firstWhere((s) => s.id == widget.setlistId,
        orElse: () => Setlist(id: '', name: ''));
    _transpose = sl.transpose[_songId] ?? 0;
  }

  void _saveTranspose() {
    if (widget.setlistId == null) return;
    final st = context.read<AppState>();
    final i = st.setlists.indexWhere((s) => s.id == widget.setlistId);
    if (i < 0) return;
    final sl = st.setlists[i];
    if (_transpose == 0) {
      sl.transpose.remove(_songId);
    } else {
      sl.transpose[_songId] = _transpose;
    }
    st.upsertSetlist(sl);
  }

  void _setTranspose(int v) {
    setState(() => _transpose = v);
    _saveTranspose();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (!_autoScroll || !_scroll.hasClients) return;
    final st = context.read<AppState>();
    final next = _scroll.offset + st.settings.scrollSpeed * dt;
    if (next >= _scroll.position.maxScrollExtent) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      setState(() => _autoScroll = false);
      _ticker.stop();
    } else {
      _scroll.jumpTo(next);
    }
  }

  void _toggleAuto() {
    setState(() => _autoScroll = !_autoScroll);
    if (_autoScroll) {
      _last = Duration.zero;
      _ticker.start();
    } else {
      _ticker.stop();
    }
  }

  bool _atBottom() =>
      _scroll.hasClients && _scroll.offset >= _scroll.position.maxScrollExtent - 4;
  bool _atTop() => !_scroll.hasClients || _scroll.offset <= 4;

  void _pageBy(double frac) {
    if (!_scroll.hasClients) return;
    final target = (_scroll.offset + _scroll.position.viewportDimension * frac)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  void _swipe(DragEndDetails d) {
    if (!_hasNav) return;
    final v = d.primaryVelocity ?? 0;
    if (v < -250 && _idx < _list.length - 1) {
      _gotoSong(_idx + 1);
    } else if (v > 250 && _idx > 0) {
      _gotoSong(_idx - 1);
    }
  }

  void _gotoSong(int newIdx) {
    if (newIdx < 0 || newIdx >= _list.length) return;
    _dir = newIdx > _idx ? 1 : -1;
    setState(() {
      _autoScroll = false;
      _songId = _list[newIdx];
      _transpose = 0;
    });
    _ticker.stop();
    _loadTranspose();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {});
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final st = context.read<AppState>();
    final action = Pedal.actionForKey(st.settings, e.logicalKey);
    if (action == 'next') {
      if (_hasNav && _atBottom() && _idx < _list.length - 1) {
        _gotoSong(_idx + 1);
      } else {
        _pageBy(0.8);
      }
      return KeyEventResult.handled;
    } else if (action == 'prev') {
      if (_hasNav && _atTop() && _idx > 0) {
        _gotoSong(_idx - 1);
      } else {
        _pageBy(-0.8);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _showDiagram(String sym) {
    final shape = ChordShapes.forChord(sym);
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(sym),
        content: shape == null
            ? const Text('Forma não disponível')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChordDiagram(shape: shape, color: scheme.primary),
                  const SizedBox(height: 4),
                  Text('forma aproximada',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
                ],
              ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
        ],
      ),
    );
  }

  void _setFont(double delta) {
    final st = context.read<AppState>();
    st.updateSettings(
        (s) => s.fontScale = (s.fontScale + delta).clamp(0.7, 2.8));
  }

  void _toggleFull() {
    setState(() => _full = !_full);
    SystemChrome.setEnabledSystemUIMode(
      _full ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    _ticker.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final base = st.songById(_songId);
    if (base == null) {
      return const Scaffold(body: Center(child: Text('Música não encontrada')));
    }
    final shown = _transpose == 0 ? base : ChordEngine.transposeSong(base, _transpose);
    final fontSize = 18.0 * st.settings.fontScale;
    final scheme = Theme.of(context).colorScheme;

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      autofocus: true,
      child: Scaffold(
        appBar: _full
            ? null
            : AppBar(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(base.title,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                    Text(
                      '${shown.key}${base.capo > 0 ? '  •  capo ${base.capo}' : ''}'
                      '${_transpose != 0 ? '  •  ${_transpose > 0 ? '+' : ''}$_transpose' : ''}'
                      '${_hasNav ? '  •  ${_idx + 1}/${_list.length}' : ''}',
                      style: TextStyle(fontSize: 12, color: scheme.primary),
                    ),
                  ],
                ),
                actions: [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.ios_share),
                    tooltip: 'Exportar',
                    onSelected: (v) {
                      if (v == 'pdf') PdfExport.printOrShare(shown);
                      if (v == 'img') {
                        ImageExport.shareImage(shown, chordColor: scheme.primary);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'pdf', child: Text('PDF / Imprimir')),
                      PopupMenuItem(value: 'img', child: Text('Imagem (PNG)')),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.fullscreen),
                    tooltip: 'Tela cheia',
                    onPressed: _toggleFull,
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Editar',
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => SongEditPage(songId: base.id))),
                  ),
                ],
              ),
        body: Stack(
          children: [
            GestureDetector(
              onHorizontalDragEnd: _swipe,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(
                    16, _full ? 28 : 8, 16, MediaQuery.of(context).size.height * 0.6),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  transitionBuilder: (child, anim) {
                    final incoming = child.key == ValueKey(_songId);
                    final begin = Offset(_dir * (incoming ? 1.0 : -1.0), 0);
                    return SlideTransition(
                      position: Tween(begin: begin, end: Offset.zero)
                          .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                      child: child,
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(_songId),
                    child: ChordChart(
                      song: shown,
                      fontSize: fontSize,
                      chordColor: scheme.primary,
                      onTapChord: _showDiagram,
                    ),
                  ),
                ),
              ),
            ),
            if (_full)
              Positioned(
                top: 6,
                right: 6,
                child: SafeArea(
                  child: Row(children: [
                    IconButton.filledTonal(
                      icon: const Icon(Icons.text_decrease),
                      tooltip: 'Fonte -',
                      onPressed: () => _setFont(-0.1),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.text_increase),
                      tooltip: 'Fonte +',
                      onPressed: () => _setFont(0.1),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.fullscreen_exit),
                      tooltip: 'Sair da tela cheia',
                      onPressed: _toggleFull,
                    ),
                  ]),
                ),
              ),
          ],
        ),
        bottomNavigationBar: _full ? null : _toolbar(st, base, scheme),
      ),
    );
  }

  Widget _toolbar(AppState st, Song base, ColorScheme scheme) {
    return SafeArea(
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              const SizedBox(width: 4),
              if (_hasNav)
                _tb(Icons.skip_previous, 'Música anterior',
                    _idx > 0 ? () => _gotoSong(_idx - 1) : null),
              _tb(Icons.remove, 'Tom -', () => _setTranspose(_transpose - 1)),
              _label('Tom'),
              _tb(Icons.add, 'Tom +', () => _setTranspose(_transpose + 1)),
              _tb(Icons.text_decrease, 'Fonte -', () => _setFont(-0.1)),
              _tb(Icons.text_increase, 'Fonte +', () => _setFont(0.1)),
              _tb(Icons.south, 'Capo -', () {
                if (base.capo > 0) {
                  base.capo--;
                  st.upsertSong(base);
                }
              }),
              _label('Capo ${base.capo}'),
              _tb(Icons.north, 'Capo +', () {
                base.capo++;
                st.upsertSong(base);
              }),
              IconButton.filledTonal(
                isSelected: _autoScroll,
                icon: Icon(_autoScroll ? Icons.pause : Icons.play_arrow),
                tooltip: 'Auto-rolagem',
                onPressed: _toggleAuto,
              ),
              _tb(Icons.fullscreen, 'Tela cheia', _toggleFull),
              if (_hasNav)
                _tb(Icons.skip_next, 'Próxima música',
                    _idx < _list.length - 1 ? () => _gotoSong(_idx + 1) : null),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tb(IconData i, String tip, VoidCallback? onTap) =>
      IconButton(icon: Icon(i), tooltip: tip, onPressed: onTap);

  Widget _label(String t) => Text(t,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13));
}
