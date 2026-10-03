import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymusic/cloud/acervo.dart';
import 'package:mymusic/cloud/cloud_state.dart';
import 'package:mymusic/data/store.dart';
import 'package:mymusic/models/song.dart';
import 'package:mymusic/ui/song_edit_page.dart';
import 'package:provider/provider.dart';

Widget _app(AppState st, Widget page) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: st),
        // nuvem desligada (sem Firebase no teste): tudo editável
        ChangeNotifierProvider(create: (_) => CloudState(st)),
        ChangeNotifierProvider(
          create: (c) => AcervoState(c.read<CloudState>(), st),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => page)),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('voltar sem mudar nada não pergunta', (t) async {
    final st = AppState()..songs.add(Song(id: 'a', title: 'Santo'));
    await t.pumpWidget(_app(st, const SongEditPage(songId: 'a')));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('abrir'), findsOneWidget);
  });

  testWidgets('voltar com mudança pergunta, e "Continuar editando" fica', (t) async {
    final st = AppState()..songs.add(Song(id: 'a', title: 'Santo'));
    await t.pumpWidget(_app(st, const SongEditPage(songId: 'a')));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Santo'), 'Santo (Capella)');
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Sair sem salvar?'), findsOneWidget);
    await t.tap(find.text('Continuar editando'));
    await t.pumpAndSettle();
    expect(find.text('Santo (Capella)'), findsOneWidget, reason: 'continua no editor');
    expect(st.songById('a')!.title, 'Santo', reason: 'nada salvo ainda');
  });

  testWidgets('música nova desistida não fica na biblioteca', (t) async {
    final st = AppState();
    final nova = Song(id: 'n', title: 'Nova música');
    await t.pumpWidget(_app(st, SongEditPage(songId: 'n', novo: nova)));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    expect(st.songs, isEmpty);
  });

  testWidgets('"Salvar" no aviso grava e sai', (t) async {
    final st = AppState();
    final nova = Song(id: 'n', title: 'Nova música');
    await t.pumpWidget(_app(st, SongEditPage(songId: 'n', novo: nova)));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Nova música'), 'Ave Maria');
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text('Salvar').last);
    await t.pumpAndSettle();
    expect(st.songById('n')?.title, 'Ave Maria');
    expect(find.text('abrir'), findsOneWidget);
  });
}
