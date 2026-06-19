import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/song.dart';

/// Exporta só as LETRAS (sem acordes) do repertório em um .txt, pros cantores.
class TextExport {
  static String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[^\w\s.-]'), '').trim();

  static String buildLyrics(String name, List<Song> songs) {
    final b = StringBuffer();
    b.writeln(name.toUpperCase());
    b.writeln();
    for (var i = 0; i < songs.length; i++) {
      final s = songs[i];
      b.writeln('${i + 1}. ${s.title}');
      if (s.artist.isNotEmpty) b.writeln(s.artist);
      b.writeln();
      for (final sec in s.sections) {
        if (sec.name.isNotEmpty) b.writeln('[${sec.name}]');
        for (final line in sec.lines) {
          // só linhas com letra de verdade (pula linhas só de acordes)
          if (line.lyric.trim().isNotEmpty) b.writeln(line.lyric);
        }
        b.writeln();
      }
      b.writeln('----------------------------------------');
      b.writeln();
    }
    return b.toString();
  }

  static Future<void> shareSetlistLyrics(String name, List<Song> songs) async {
    final text = buildLyrics(name, songs);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_sanitize(name)} - letras.txt');
    await file.writeAsString(text);
    await Share.shareXFiles([XFile(file.path)], subject: '$name — letras');
  }
}
