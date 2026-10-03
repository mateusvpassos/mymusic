import '../models/song.dart';

/// Resultado da busca de uma música.
class SongHit {
  final Song song;
  final bool inLyric; // só achou na letra (não no título/artista/tag)
  final String? snippet; // a linha da letra onde achou
  const SongHit(this.song, {this.inLyric = false, this.snippet});
}

/// Busca que ignora acento e maiúscula ("oleo" acha "Teu Óleo Santo") e olha
/// também a letra, p/ achar a música lembrando só de um pedaço do canto.
class SongSearch {
  static const _de = 'áàâãäåéèêëíìîïóòôõöúùûüçñýÿ';
  static const _para = 'aaaaaaeeeeiiiiooooouuuucnyy';

  static String fold(String s) {
    final low = s.toLowerCase();
    final b = StringBuffer();
    for (final ch in low.split('')) {
      final i = _de.indexOf(ch);
      b.write(i >= 0 ? _para[i] : ch);
    }
    return b.toString();
  }

  /// Músicas que batem com [query], título/artista/tag primeiro e depois as
  /// que só têm o trecho na letra. Várias palavras = todas têm que aparecer.
  static List<SongHit> run(Iterable<Song> songs, String query) {
    final q = fold(query.trim());
    if (q.isEmpty) return [for (final s in songs) SongHit(s)];
    final words = q.split(RegExp(r'\s+'));
    final porNome = <SongHit>[], porLetra = <SongHit>[];
    for (final s in songs) {
      final meta = fold('${s.title} ${s.artist} ${s.tags.join(' ')}');
      if (words.every(meta.contains)) {
        porNome.add(SongHit(s));
        continue;
      }
      // na letra, a frase inteira (mais preciso que palavras soltas)
      for (final sec in s.sections) {
        String? achou;
        for (final l in sec.lines) {
          if (fold(l.lyric).contains(q)) {
            achou = l.lyric.trim();
            break;
          }
        }
        if (achou != null) {
          porLetra.add(SongHit(s, inLyric: true, snippet: achou));
          break;
        }
      }
    }
    return [...porNome, ...porLetra];
  }
}
