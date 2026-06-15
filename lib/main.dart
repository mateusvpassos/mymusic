import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'data/store.dart';
import 'sync/drive_sync.dart';
import 'ui/library_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final state = AppState();
  final sync = SyncState();
  state.onPersist = () => sync.scheduleAuto(state);
  runApp(MyApp(state: state, sync: sync));
  state.load();
  sync.trySilent().then((_) {
    if (sync.signedIn) sync.sync(state);
  });
}

class MyApp extends StatelessWidget {
  final AppState state;
  final SyncState sync;
  const MyApp({super.key, required this.state, required this.sync});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        ChangeNotifierProvider.value(value: sync),
      ],
      child: Consumer<AppState>(
        builder: (context, st, _) {
          final seed = Color(st.settings.seedColor);
          final scheme = ColorScheme.fromSeed(
            seedColor: seed,
            brightness: st.settings.dark ? Brightness.dark : Brightness.light,
          );
          return MaterialApp(
            title: 'MyMusic',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: scheme,
              useMaterial3: true,
              scaffoldBackgroundColor: scheme.surface,
              appBarTheme: AppBarTheme(
                backgroundColor: scheme.surface,
                foregroundColor: scheme.onSurface,
                centerTitle: false,
                elevation: 0,
              ),
              cardTheme: CardThemeData(
                clipBehavior: Clip.antiAlias,
                elevation: 0,
                color: scheme.surfaceContainerHigh,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
            home: const LibraryPage(),
          );
        },
      ),
    );
  }
}
