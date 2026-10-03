import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../core/chord_engine.dart';
import '../core/chord_shapes.dart';
import '../core/docx_export.dart';
import '../core/image_export.dart';
import '../core/pdf_export.dart';
import '../core/pedal.dart';
import '../data/store.dart';
import '../live/live_page.dart';
import '../live/live_session.dart';
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

  /// Quantas telas de música estão abertas — a sessão ao vivo abre uma
  /// quando quem conduz troca de música e quem segue está em outra tela.
  static int openCount = 0;
}

class _SongViewPageState extends State<SongViewPage>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  final _focus = FocusNode();
  late String _songId;
  int _transpose = 0;
  bool _autoScroll = false;
  bool _full = false;
  bool _capo = true; // aplica capotraste de verdade nos acordes mostrados
  int _dir = 1; // direção da última troca (1 = próxima, -1 = anterior)
  Timer? _metro;
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  // sessão ao vivo
  late final LiveSession _live = context.read<LiveSession>();
  StreamSubscription<LiveNav>? _navSub;
  StreamSubscription<LiveScroll>? _scrollSub;
  Timer? _scrollPub;
  bool _scrollDirty = false;

  // navegação: setlist (se veio de um repertório) OU toda a biblioteca
  List<String> get _list =>
      widget.setlistSongIds ??
      context.read<AppState>().songs.map((s) => s.id).toList();
  int get _idx => _list.indexOf(_songId);
  bool get _hasNav => _list.length > 1;

  @override
  void initState() {
    super.initState();
    _songId = widget.songId;
    _ticker = createTicker(_onTick);
    WakelockPlus.enable();
    _loadTranspose();
    SongViewPage.openCount++;
    _navSub = _live.navStream.listen(_onRemoteNav);
    _scrollSub = _live.scrollStream.listen(_onRemoteScroll);
    _scroll.addListener(_onScrollChanged);
    // seguindo e abrindo a mesma música de quem conduz: já cai no tom dele
    final n = _live.lastNav;
    if (_live.following && n != null && n.songId == _songId) {
      _transpose = n.transpose;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      if (_live.conducting) {
        _publishNav();
      } else if (_live.following && _live.lastScroll?.songId == _songId) {
        _onRemoteScroll(_live.lastScroll!);
      }
    });
  }

  // ---- sessão ao vivo ----

  void _publishNav() {
    if (!_live.conducting) return;
    final st = context.read<AppState>();
    final s = st.songById(_songId);
    if (s == null) return;
    final sl = widget.setlistId == null
        ? null
        : st.setlistById(widget.setlistId!);
    _live.publishNav(s, setlist: sl, transpose: _transpose);
  }

  // rolagem em fração da altura do CONTEÚDO (sem o respiro de 60% da tela
  // no fim): aparelhos de tamanho e fonte diferentes caem no mesmo trecho
  double _contentH() {
    final p = _scroll.position;
    return p.maxScrollExtent +
        p.viewportDimension -
        MediaQuery.of(context).size.height * 0.6;
  }

  // manda no máximo a cada 120ms, mas sempre a última posição
  void _onScrollChanged() {
    if (!_live.conducting || !_scroll.hasClients) return;
    if (_scrollPub?.isActive ?? false) {
      _scrollDirty = true;
      return;
    }
    _sendScroll();
    _scrollPub = Timer(const Duration(milliseconds: 120), () {
      if (_scrollDirty && mounted) {
        _scrollDirty = false;
        _sendScroll();
      }
    });
  }

  void _sendScroll() {
    final h = _contentH();
    _live.publishScroll(
      _songId,
      h <= 0 ? 0 : (_scroll.offset / h).clamp(0.0, 1.0),
    );
  }

  void _onRemoteScroll(LiveScroll r) {
    if (r.songId != _songId || !_scroll.hasClients) return;
    final alvo = (r.frac * _contentH()).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if ((alvo - _scroll.offset).abs() < 1) return;
    _scroll.animateTo(
      alvo,
      duration: const Duration(milliseconds: 160),
      curve: Curves.linear,
    );
  }

  // navegação que chegou enquanto havia algo por cima (editor, diagrama):
  // aplica quando a tela da música voltar a ser a de cima
  LiveNav? _pendente;

  void _aplicarPendente() {
    final n = _pendente;
    _pendente = null;
    if (n != null && mounted && _live.following) _onRemoteNav(n);
  }

  void _onRemoteNav(LiveNav n) {
    if (!mounted) return;
    // pushReplacement troca a rota do TOPO: com o editor aberto por cima,
    // descartaria a edição sem perguntar
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      _pendente = n;
      return;
    }
    if (n.songId == _songId) {
      if (n.transpose != _transpose) setState(() => _transpose = n.transpose);
      return;
    }
    // quem conduz foi p/ outro repertório (ou p/ a biblioteca): reabre no
    // contexto certo, p/ o "próxima música" daqui bater com o de lá
    if (n.setlistId != widget.setlistId) {
      final sl = n.setlistId == null
          ? null
          : context.read<AppState>().setlistById(n.setlistId!);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SongViewPage(
            songId: n.songId,
            setlistId: sl?.id,
            setlistSongIds: sl == null ? null : List.of(sl.songIds),
          ),
        ),
      );
      return;
    }
    final i = _list.indexOf(n.songId);
    if (i >= 0) {
      _gotoSong(i);
    } else {
      setState(() => _songId = n.songId);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    setState(() => _transpose = n.transpose);
  }

  void _loadTranspose() {
    if (widget.setlistId == null) return;
    final st = context.read<AppState>();
    final sl = st.setlists.firstWhere(
      (s) => s.id == widget.setlistId,
      orElse: () => Setlist(id: '', name: ''),
    );
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
    _publishNav();
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
      _scroll.hasClients &&
      _scroll.offset >= _scroll.position.maxScrollExtent - 4;
  bool _atTop() => !_scroll.hasClients || _scroll.offset <= 4;

  void _pageBy(double frac) {
    if (!_scroll.hasClients) return;
    final target = (_scroll.offset + _scroll.position.viewportDimension * frac)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
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
    _publishNav();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final st = context.read<AppState>();
    final action = Pedal.actionForKey(st.settings, e.logicalKey);
    if (action == 'next') {
      if (_hasNav && _atBottom() && _idx < _list.length - 1) {
        _gotoSong(_idx + 1);
      } else {
        _pageBy(st.settings.pageStep);
      }
      return KeyEventResult.handled;
    } else if (action == 'prev') {
      if (_hasNav && _atTop() && _idx > 0) {
        _gotoSong(_idx - 1);
      } else {
        _pageBy(-st.settings.pageStep);
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
                  Text(
                    'forma aproximada',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ],
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    ).then((_) => _aplicarPendente());
  }

  // versão forte/escura da cor do tema, p/ marcar bem em fundo branco (PDF/imagem)
  Color _strongColor() {
    final st = context.read<AppState>();
    final hsl = HSLColor.fromColor(Color(st.settings.seedColor));
    return hsl
        .withSaturation((hsl.saturation * 1.25).clamp(0.85, 1.0))
        .withLightness(0.42)
        .toColor();
  }

  List<String> _uniqueChords(Song song) {
    final seen = <String>{};
    final out = <String>[];
    for (final sec in song.sections) {
      for (final l in sec.lines) {
        for (final c in l.chords) {
          // (2x), |, N.C. são marcação, não acorde p/ mostrar diagrama
          if (ChordEngine.isChordSymbol(c.sym) && seen.add(c.sym)) {
            out.add(c.sym);
          }
        }
      }
    }
    return out;
  }

  Widget _chordBar(List<String> chords, ColorScheme scheme, Color chordColor) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: chords.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) => ActionChip(
          label: Text(
            chords[i],
            style: TextStyle(color: chordColor, fontWeight: FontWeight.w700),
          ),
          visualDensity: VisualDensity.compact,
          onPressed: () => _showDiagram(chords[i]),
        ),
      ),
    );
  }

  void _setFont(double delta) {
    final st = context.read<AppState>();
    st.updateSettings(
      (s) => s.fontScale = (s.fontScale + delta).clamp(0.7, 2.8),
    );
  }

  void _toggleMetro(int bpm) {
    if (_metro != null) {
      _metro!.cancel();
      setState(() => _metro = null);
      return;
    }
    if (bpm <= 0) return;
    void tick() {
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.lightImpact();
    }

    tick();
    setState(() {
      _metro = Timer.periodic(
        Duration(milliseconds: (60000 / bpm).round()),
        (_) => tick(),
      );
    });
  }

  void _toggleFull() {
    setState(() => _full = !_full);
    SystemChrome.setEnabledSystemUIMode(
      _full ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  @override
  void dispose() {
    SongViewPage.openCount--;
    _navSub?.cancel();
    _scrollSub?.cancel();
    _scrollPub?.cancel();
    _metro?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // em sessão ao vivo a tela continua acesa fora da música também (quem
    // segue espera na tela inicial o próximo canto)
    if (!_live.active) WakelockPlus.disable();
    _ticker.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final live = context.watch<LiveSession>();
    final base = st.songById(_songId);
    if (base == null) {
      return const Scaffold(body: Center(child: Text('Música não encontrada')));
    }
    final steps = _transpose - (_capo ? base.capo : 0);
    final shown = steps == 0 ? base : ChordEngine.transposeSong(base, steps);
    final fontSize = 18.0 * st.settings.fontScale;
    final scheme = Theme.of(context).colorScheme;
    // modo claro: primary do M3 fica pastel — usa versão saturada/forte
    final chordColor = st.settings.dark ? scheme.primary : _strongColor();
    final uniqueChords = _uniqueChords(shown);

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
                    Text(
                      base.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      '${shown.key}'
                      '${base.capo > 0 ? '  •  capo ${base.capo}${_capo ? '' : ' (off)'}' : ''}'
                      '${_transpose != 0 ? '  •  ${_transpose > 0 ? '+' : ''}$_transpose' : ''}'
                      '${base.bpm > 0 ? '  •  ${base.bpm} BPM' : ''}'
                      '${_hasNav ? '  •  ${_idx + 1}/${_list.length}' : ''}',
                      style: TextStyle(fontSize: 12, color: scheme.primary),
                    ),
                    if (live.active)
                      // toque abre a sessão (ex.: passar p/ "livre" sem sair da música)
                      InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const LivePage()),
                        ),
                        child: Text(
                          live.reconnecting
                              ? 'ao vivo: reconectando...'
                              : live.conducting
                              ? 'ao vivo: conduzindo (${live.others} seguindo)'
                              : live.following
                              ? 'ao vivo: seguindo'
                              : 'ao vivo: livre',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                            color: live.reconnecting
                                ? scheme.error
                                : scheme.tertiary,
                          ),
                        ),
                      ),
                  ],
                ),
                actions: [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.ios_share),
                    tooltip: 'Exportar',
                    onSelected: (v) {
                      final strong = _strongColor();
                      final prefix = widget.setlistId != null
                          ? '${_idx + 1}. '
                          : '';
                      if (v == 'pdf') {
                        PdfExport.printOrShare(
                          shown,
                          colorArgb: strong.toARGB32(),
                          namePrefix: prefix,
                        );
                      }
                      if (v == 'img') {
                        ImageExport.shareImage(
                          shown,
                          chordColor: strong,
                          namePrefix: prefix,
                        );
                      }
                      if (v == 'docx') {
                        DocxExport.shareSong(
                          shown,
                          chordColor: strong,
                          namePrefix: prefix,
                        );
                      }
                      st.logEvent(
                        'exportou',
                        'musica',
                        base.title,
                        details: ['Formato: ${v.toUpperCase()}'],
                      );
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'pdf',
                        child: Text('PDF / Imprimir'),
                      ),
                      PopupMenuItem(value: 'docx', child: Text('Word (.docx)')),
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
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SongEditPage(songId: base.id),
                      ),
                    ).then((_) => _aplicarPendente()),
                  ),
                ],
              ),
        body: Column(
          children: [
            if (!_full && uniqueChords.isNotEmpty)
              _chordBar(uniqueChords, scheme, chordColor),
            if (!_full && base.notes.isNotEmpty)
              Container(
                width: double.infinity,
                color: scheme.secondaryContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.sticky_note_2_outlined,
                      size: 16,
                      color: scheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        base.notes,
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  GestureDetector(
                    onHorizontalDragEnd: _swipe,
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: EdgeInsets.fromLTRB(
                        16,
                        _full ? 28 : 8,
                        16,
                        MediaQuery.of(context).size.height * 0.6,
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        transitionBuilder: (child, anim) {
                          final incoming = child.key == ValueKey(_songId);
                          final begin = Offset(
                            _dir * (incoming ? 1.0 : -1.0),
                            0,
                          );
                          return SlideTransition(
                            position: Tween(begin: begin, end: Offset.zero)
                                .animate(
                                  CurvedAnimation(
                                    parent: anim,
                                    curve: Curves.easeOutCubic,
                                  ),
                                ),
                            child: child,
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey(_songId),
                          child: ChordChart(
                            song: shown,
                            fontSize: fontSize,
                            chordColor: chordColor,
                            onTapChord: _showDiagram,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_autoScroll)
                    Positioned(
                      top: MediaQuery.of(context).size.height * 0.30,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Container(
                          height: fontSize * 2.6,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.10),
                            border: Border(
                              top: BorderSide(
                                color: scheme.primary.withValues(alpha: 0.35),
                              ),
                              bottom: BorderSide(
                                color: scheme.primary.withValues(alpha: 0.35),
                              ),
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
                        child: Row(
                          children: [
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
                          ],
                        ),
                      ),
                    ),
                ],
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
                _tb(
                  Icons.skip_previous,
                  'Música anterior',
                  _idx > 0 ? () => _gotoSong(_idx - 1) : null,
                ),
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
              if (base.capo > 0)
                IconButton(
                  isSelected: _capo,
                  icon: Icon(_capo ? Icons.album : Icons.album_outlined),
                  tooltip: _capo
                      ? 'Acordes com capo (ligado)'
                      : 'Acordes com capo (desligado)',
                  onPressed: () => setState(() => _capo = !_capo),
                ),
              IconButton.filledTonal(
                isSelected: _autoScroll,
                icon: Icon(_autoScroll ? Icons.pause : Icons.play_arrow),
                tooltip: 'Auto-rolagem',
                onPressed: _toggleAuto,
              ),
              if (base.bpm > 0)
                IconButton(
                  isSelected: _metro != null,
                  icon: Icon(
                    _metro != null ? Icons.av_timer : Icons.av_timer_outlined,
                  ),
                  tooltip: 'Metrônomo ${base.bpm}',
                  onPressed: () => _toggleMetro(base.bpm),
                ),
              _tb(Icons.fullscreen, 'Tela cheia', _toggleFull),
              if (_hasNav)
                _tb(
                  Icons.skip_next,
                  'Próxima música',
                  _idx < _list.length - 1 ? () => _gotoSong(_idx + 1) : null,
                ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tb(IconData i, String tip, VoidCallback? onTap) =>
      IconButton(icon: Icon(i), tooltip: tip, onPressed: onTap);

  Widget _label(String t) => Text(
    t,
    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
  );
}
