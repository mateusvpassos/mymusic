import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/chord_engine.dart';
import '../data/store.dart';
import '../models/song.dart';
import 'package:provider/provider.dart';

class _ChordDrag {
  final String sym;
  final Chord? origin;
  final SongLine? originLine;
  _ChordDrag(this.sym, this.origin, this.originLine);
}

class SongEditPage extends StatefulWidget {
  final String songId;
  const SongEditPage({super.key, required this.songId});
  @override
  State<SongEditPage> createState() => _SongEditPageState();
}

class _SongEditPageState extends State<SongEditPage> {
  late Song _song;
  late TextEditingController _title;
  late TextEditingController _artist;
  late TextEditingController _key;
  late TextEditingController _text;
  late TextEditingController _notes;
  late TextEditingController _bpm;
  final List<DateTime> _taps = [];
  int _mode = 0; // 0 = Acordes (visual), 1 = Texto
  final List<String> _undo = [];
  String _current = '';

  final List<String> _palette = [
    'C', 'D', 'E', 'F', 'G', 'A', 'B',
    'Cm', 'Dm', 'Em', 'Fm', 'Gm', 'Am', 'Bm',
    'C7', 'D7', 'E7', 'G7', 'A7', 'B7',
    'Cmaj7', 'Dm7', 'Em7', 'Gsus4', 'A/C#', 'D/F#',
  ];

  @override
  void initState() {
    super.initState();
    final src = context.read<AppState>().songById(widget.songId)!;
    _song = src.copy();
    _title = TextEditingController(text: _song.title);
    _artist = TextEditingController(text: _song.artist);
    _key = TextEditingController(text: _song.key);
    _text = TextEditingController(text: ChordEngine.serializeSections(_song.sections));
    _notes = TextEditingController(text: _song.notes);
    _bpm = TextEditingController(text: _song.bpm > 0 ? '${_song.bpm}' : '');
    _current = ChordEngine.serializeSections(_song.sections);
  }

  // registra mudança p/ undo (snapshot anterior já está em _current)
  void _recordChange() {
    _undo.add(_current);
    if (_undo.length > 40) _undo.removeAt(0);
    _current = ChordEngine.serializeSections(_song.sections);
    setState(() {});
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    _current = _undo.removeLast();
    setState(() {
      _song.sections = ChordEngine.importText(_current);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _key.dispose();
    _text.dispose();
    _notes.dispose();
    _bpm.dispose();
    super.dispose();
  }

  void _save() {
    if (_mode == 1) _applyText();
    _song.title = _title.text.trim().isEmpty ? 'Sem título' : _title.text.trim();
    _song.artist = _artist.text.trim();
    _song.key = _key.text.trim().isEmpty ? 'C' : _key.text.trim();
    _song.notes = _notes.text.trim();
    _song.bpm = int.tryParse(_bpm.text.trim()) ?? 0;
    context.read<AppState>().upsertSong(_song);
    Navigator.pop(context);
  }

  void _applyText() {
    _song.sections = ChordEngine.importText(_text.text);
  }

  void _maybeSuggestKey() {
    if (_key.text.trim().isNotEmpty && _key.text.trim() != 'C') return;
    final k = ChordEngine.suggestKey(_song.sections);
    if (k != null) _key.text = k;
  }

  Future<void> _importDialog() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Expanded(child: Text('Importar cifra')),
            TextButton.icon(
              icon: const Icon(Icons.content_paste, size: 18),
              label: const Text('Colar'),
              onPressed: () async {
                final d = await Clipboard.getData(Clipboard.kTextPlain);
                if (d?.text != null) ctrl.text = d!.text!;
              },
            ),
          ],
        ),
        content: SizedBox(
          width: 600,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 14,
            style: const TextStyle(fontFamily: 'ChordMono', fontSize: 13),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Cole a cifra aqui (acordes acima da letra ou [G]letra)...',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Importar')),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      _song.sections = ChordEngine.importText(ctrl.text);
      _text.text = ChordEngine.serializeSections(_song.sections);
      _maybeSuggestKey();
      _mode = 0;
      _recordChange();
    }
  }

  void _exportText() {
    final t = ChordEngine.serializeSections(
        _mode == 1 ? ChordEngine.importText(_text.text) : _song.sections);
    Clipboard.setData(ClipboardData(text: t));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cifra copiada (texto)')),
    );
  }

  void _syncTextFromModel() {
    _text.text = ChordEngine.serializeSections(_song.sections);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar'),
        actions: [
          IconButton(
            tooltip: 'Desfazer',
            icon: const Icon(Icons.undo),
            onPressed: _undo.isEmpty ? null : _undoLast,
          ),
          IconButton(
            tooltip: 'Importar cifra',
            icon: const Icon(Icons.paste),
            onPressed: _importDialog,
          ),
          IconButton(
            tooltip: 'Copiar como texto',
            icon: const Icon(Icons.copy),
            onPressed: _exportText,
          ),
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Salvar'),
          ),
        ],
      ),
      body: Column(
        children: [
          _meta(scheme),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Acordes'), icon: Icon(Icons.touch_app)),
                ButtonSegment(value: 1, label: Text('Texto'), icon: Icon(Icons.notes)),
              ],
              selected: {_mode},
              onSelectionChanged: (s) {
                setState(() {
                  if (_mode == 1 && s.first == 0) _applyText();
                  if (_mode == 0 && s.first == 1) _syncTextFromModel();
                  _mode = s.first;
                });
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _mode == 0 ? _visual(scheme) : _textEditor()),
        ],
      ),
    );
  }

  void _tapTempo() {
    final now = DateTime.now();
    if (_taps.isNotEmpty && now.difference(_taps.last).inMilliseconds > 2000) {
      _taps.clear();
    }
    _taps.add(now);
    if (_taps.length >= 2) {
      final intervals = <int>[];
      for (var i = 1; i < _taps.length; i++) {
        intervals.add(_taps[i].difference(_taps[i - 1]).inMilliseconds);
      }
      final avg = intervals.reduce((a, b) => a + b) / intervals.length;
      final bpm = (60000 / avg).round();
      setState(() => _bpm.text = '$bpm');
    }
    if (_taps.length > 6) _taps.removeAt(0);
  }

  void _addTag() async {
    final ctrl = TextEditingController();
    final t = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tag / categoria'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ex.: adoração, ceia, natal'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Add')),
        ],
      ),
    );
    final v = t?.trim().toLowerCase();
    if (v != null && v.isNotEmpty && !_song.tags.contains(v)) {
      setState(() => _song.tags.add(v));
    }
  }

  Widget _meta(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          TextField(
            controller: _title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(hintText: 'Título', isDense: true),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _artist,
                  decoration: const InputDecoration(hintText: 'Artista', isDense: true),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _key,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(labelText: 'Tom', isDense: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final t in _song.tags)
                Chip(
                  label: Text(t),
                  visualDensity: VisualDensity.compact,
                  onDeleted: () => setState(() => _song.tags.remove(t)),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('tag'),
                visualDensity: VisualDensity.compact,
                onPressed: _addTag,
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _notes,
            maxLines: 2,
            minLines: 1,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Anotações (ex.: entra suave, repete 2x)',
              isDense: true,
              prefixIcon: Icon(Icons.sticky_note_2_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _bpm,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'BPM', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _tapTempo,
                icon: const Icon(Icons.touch_app, size: 18),
                label: const Text('Tap tempo'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- modo TEXTO ----------
  Widget _textEditor() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Use [Acorde] antes da sílaba. Linha com # = seção. Ex.:  O [G]esplendor de um [D]Rei',
            style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TextField(
              controller: _text,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'ChordMono', fontSize: 15, height: 1.4),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- modo VISUAL (drag) ----------
  Widget _visual(ColorScheme scheme) {
    return Column(
      children: [
        Expanded(
          child: ReorderableListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            buildDefaultDragHandles: false,
            onReorder: (a, b) {
              setState(() {
                if (b > a) b--;
                final s = _song.sections.removeAt(a);
                _song.sections.insert(b, s);
              });
              _recordChange();
            },
            footer: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: _addSection,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar seção'),
              ),
            ),
            children: [
              for (int si = 0; si < _song.sections.length; si++)
                _sectionCard(si, scheme),
            ],
          ),
        ),
        _paletteBar(scheme),
      ],
    );
  }

  Widget _sectionCard(int si, ColorScheme scheme) {
    final sec = _song.sections[si];
    return Card(
      key: ObjectKey(sec),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: si,
                  child: const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.drag_indicator, size: 20),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _renameSection(sec),
                    child: Text(
                      sec.name.isEmpty ? '(sem nome)' : sec.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (v) {
                    if (v == 'rename') _renameSection(sec);
                    if (v == 'dup') {
                      setState(() => _song.sections.insert(si + 1, sec.copy()));
                      _recordChange();
                    }
                    if (v == 'del') {
                      setState(() => _song.sections.removeAt(si));
                      _recordChange();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Renomear')),
                    PopupMenuItem(value: 'dup', child: Text('Duplicar')),
                    PopupMenuItem(value: 'del', child: Text('Excluir')),
                  ],
                ),
              ],
            ),
            for (final line in sec.lines)
              _EditableLine(
                line: line,
                chordColor: scheme.primary,
                onChanged: _recordChange,
                onEditChord: (c) => _editChord(line, c),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  setState(() => sec.lines.add(SongLine('', [])));
                  _recordChange();
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('linha'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paletteBar(ColorScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            const SizedBox(width: 8),
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Text('Acordes', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _palette.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  if (i == _palette.length) {
                    return ActionChip(
                      label: const Icon(Icons.add, size: 18),
                      onPressed: _addCustomChord,
                    );
                  }
                  return _PaletteChip(sym: _palette[i], color: scheme.primary);
                },
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  void _addCustomChord() async {
    final ctrl = TextEditingController();
    final sym = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Acorde'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ex.: F#m7'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Usar')),
        ],
      ),
    );
    final t = sym?.trim() ?? '';
    if (t.isNotEmpty) {
      setState(() {
        if (!_palette.contains(t)) _palette.insert(0, t);
      });
    }
  }

  void _editChord(SongLine line, Chord c) async {
    final ctrl = TextEditingController(text: c.sym);
    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Editar acorde'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, '__del__'),
            child: const Text('Excluir'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (res == null) return;
    if (res == '__del__') {
      line.chords.remove(c);
    } else if (res.trim().isNotEmpty) {
      c.sym = res.trim();
    }
    _recordChange();
  }

  void _addSection() {
    setState(() => _song.sections.add(Section('Nova seção', [SongLine('', [])])));
    _recordChange();
  }

  void _renameSection(Section sec) async {
    final ctrl = TextEditingController(text: sec.name);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nome da seção'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, '__del__'),
              child: const Text('Excluir seção')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('OK')),
        ],
      ),
    );
    if (name == null) return;
    setState(() {
      if (name == '__del__') {
        _song.sections.remove(sec);
      } else {
        sec.name = name.trim();
      }
    });
    _recordChange();
  }
}

/// Chip arrastável da paleta.
class _PaletteChip extends StatelessWidget {
  final String sym;
  final Color color;
  const _PaletteChip({required this.sym, required this.color});

  @override
  Widget build(BuildContext context) {
    final chip = Chip(
      label: Text(sym, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      visualDensity: VisualDensity.compact,
    );
    return Draggable<_ChordDrag>(
      data: _ChordDrag(sym, null, null),
      feedback: Material(color: Colors.transparent, child: _ghost(sym, color)),
      child: chip,
    );
  }

  Widget _ghost(String s, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(s, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      );
}

/// Uma linha editável: letra (monospace) + acordes posicionados/arrastáveis,
/// com DragTarget que calcula a coluna pelo offset do drop.
class _EditableLine extends StatefulWidget {
  final SongLine line;
  final Color chordColor;
  final VoidCallback onChanged;
  final void Function(Chord) onEditChord;
  const _EditableLine({
    required this.line,
    required this.chordColor,
    required this.onChanged,
    required this.onEditChord,
  });

  @override
  State<_EditableLine> createState() => _EditableLineState();
}

class _EditableLineState extends State<_EditableLine> {
  final _lyricKey = GlobalKey();

  static const _lyricStyle = TextStyle(fontFamily: 'ChordMono', fontSize: 16, height: 1.25);

  double get _charW {
    final tp = TextPainter(
      text: const TextSpan(text: 'M', style: _lyricStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.size.width;
  }

  // posições x sem overlap (empurra acorde largo p/ direita), por objeto Chord
  Map<Chord, double> _placeX(SongLine line, TextStyle chordStyle, double charW) {
    final sorted = [...line.chords]..sort((a, b) => a.idx.compareTo(b.idx));
    const gap = 8.0;
    final map = <Chord, double>{};
    double prevRight = -1e9;
    for (final c in sorted) {
      final tp = TextPainter(
        text: TextSpan(text: '${c.sym} ', style: chordStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      var x = c.idx.clamp(0, line.lyric.length) * charW;
      if (x < prevRight + gap) x = prevRight + gap;
      map[c] = x;
      prevRight = x + tp.size.width;
    }
    return map;
  }

  int _idxFromGlobal(Offset global) {
    final box = _lyricKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return 0;
    final local = box.globalToLocal(global);
    final i = (local.dx / _charW).round();
    return i.clamp(0, widget.line.lyric.length);
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final charW = _charW;
    final chordStyle = TextStyle(
      fontFamily: 'ChordMono',
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: widget.chordColor,
    );
    final xOf = _placeX(line, chordStyle, charW);
    final chordRow = SizedBox(
      height: line.chords.isEmpty ? 20 : 22,
      child: Stack(
        children: [
          for (final c in line.chords)
            Positioned(
              left: xOf[c]!,
              child: Draggable<_ChordDrag>(
                data: _ChordDrag(c.sym, c, line),
                feedback: Material(
                  color: Colors.transparent,
                  child: Text(c.sym, style: chordStyle.copyWith(fontSize: 17)),
                ),
                childWhenDragging: Opacity(opacity: 0.3, child: Text(c.sym, style: chordStyle)),
                child: GestureDetector(
                  onTap: () => widget.onEditChord(c),
                  child: Text(c.sym, style: chordStyle),
                ),
              ),
            ),
        ],
      ),
    );

    return DragTarget<_ChordDrag>(
      onAcceptWithDetails: (d) {
        final idx = _idxFromGlobal(d.offset);
        setState(() {
          if (d.data.origin != null && d.data.originLine != null) {
            d.data.originLine!.chords.remove(d.data.origin);
          }
          line.chords.add(Chord(d.data.sym, idx));
        });
        widget.onChanged();
      },
      builder: (context, cand, rej) {
        return Container(
          color: cand.isNotEmpty
              ? widget.chordColor.withValues(alpha: 0.08)
              : Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              chordRow,
              Text(
                line.lyric.isEmpty ? ' ' : line.lyric,
                key: _lyricKey,
                style: _lyricStyle,
                maxLines: 1,
                softWrap: false,
                textScaler: TextScaler.noScaling,
              ),
            ],
          ),
        );
      },
    );
  }
}
