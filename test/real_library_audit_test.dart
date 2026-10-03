// Diagnóstico da biblioteca real do usuário (não versionada): só roda se
// MYMUSIC_DATA apontar p/ um mymusic_data.json. Não falha — imprime achados.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymusic/core/chord_engine.dart';
import 'package:mymusic/core/pdf_export.dart';
import 'package:mymusic/data/store.dart';
import 'package:mymusic/models/song.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // fontes do PDF vêm dos assets
  final path = Platform.environment['MYMUSIC_DATA'];
  test('auditoria da biblioteca real', () {
    if (path == null) return;
    final j = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    final songs = (j['songs'] as List).map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
    final naoReconhecidos = <String, Set<String>>{};
    final linhasDeAcordeComoLetra = <String>[];
    final instaveis = <String>[];
    final chordTok = RegExp(r'\S+');
    if (Platform.environment['REPAIR'] == '1') {
      var tot = 0;
      for (final s in songs) {
        final n = ChordEngine.repairChordLines(s.sections);
        if (n > 0) {
          tot += n;
          // ignore: avoid_print
          print('REPARADA: ${s.title} ($n linha(s))');
        }
      }
      // ignore: avoid_print
      print('TOTAL REPARADO: $tot');
    }
    for (final s in songs) {
      for (final sec in s.sections) {
        for (final l in sec.lines) {
          for (final c in l.chords) {
            if (!ChordEngine.isChordSymbol(c.sym)) {
              naoReconhecidos.putIfAbsent(c.sym, () => {}).add(s.title);
            }
          }
          // letra sem acorde que o parser NOVO leria como linha de acordes
          if (l.chords.isEmpty && l.lyric.trim().isNotEmpty) {
            final re = ChordEngine.importText('${l.lyric}\nx');
            final first = re.expand((x) => x.lines).first;
            if (first.chords.isNotEmpty && chordTok.allMatches(l.lyric).isNotEmpty) {
              linhasDeAcordeComoLetra.add('${s.title}: "${l.lyric.trim()}"');
            }
          }
        }
      }
      // ida e volta pelo editor
      String dump(List<Section> x) => x
          .map((sec) => '${sec.name}|${sec.lines.map((l) => '${l.lyric.trimRight()}'
              '${l.chords.map((c) => '${c.sym}@${c.idx}').join(',')}').join(';')}')
          .join('/');
      final a = s.sections.map((x) => x.copy()).toList();
      ChordEngine.trimSectionEnds(a);
      final b = ChordEngine.importText(ChordEngine.serializeSections(a));
      if (dump(a) != dump(b)) {
        instaveis.add(s.title);
        final la = dump(a).split(RegExp('[;/]')), lb = dump(b).split(RegExp('[;/]'));
        for (var i = 0; i < la.length || i < lb.length; i++) {
          final x = i < la.length ? la[i] : '<nada>', y = i < lb.length ? lb[i] : '<nada>';
          if (x != y) {
            // ignore: avoid_print
            print('  DIFF ${s.title} #$i  ANTES: $x  ||  DEPOIS: $y');
            break;
          }
        }
      }
    }
    // ignore: avoid_print
    print('MUSICAS: ${songs.length}');
    // ignore: avoid_print
    print('ACORDES NAO RECONHECIDOS (${naoReconhecidos.length}):');
    // ignore: avoid_print
    naoReconhecidos.forEach((k, v) => print('   "$k"  em ${v.take(3).join(' | ')}'));
    // ignore: avoid_print
    print('LINHAS DE ACORDE SALVAS COMO LETRA (${linhasDeAcordeComoLetra.length}):');
    for (final x in linhasDeAcordeComoLetra.take(40)) {
      // ignore: avoid_print
      print('   $x');
    }
    // ignore: avoid_print
    print('INSTAVEIS NA IDA E VOLTA (${instaveis.length}): ${instaveis.join(' | ')}');
  });

  test('gera PDF de um repertório real (REPERTORIO=nome)', () async {
    final nome = Platform.environment['REPERTORIO'];
    if (path == null || nome == null) return;
    final st = AppState()
      ..applyLoaded(jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>);
    final sl = st.setlists.firstWhere((x) => x.name == nome);
    final songs = [
      for (final id in sl.songIds)
        if (st.songById(id) case final s?)
          (sl.transpose[id] ?? 0) == 0 ? s : ChordEngine.transposeSong(s, sl.transpose[id]!)
    ];
    final doc = await PdfExport.setlistDoc(sl.name, songs);
    final f = File('build/real-setlist.pdf');
    await f.writeAsBytes(await doc.save());
    // ignore: avoid_print
    print('PDF: ${songs.length} músicas, ${doc.document.pdfPageList.pages.length} páginas');
  });
}
