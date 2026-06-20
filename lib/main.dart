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
          final radius = BorderRadius.circular(16);
          return MaterialApp(
            title: 'MyMusic',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: scheme,
              useMaterial3: true,
              scaffoldBackgroundColor: scheme.surface,
              splashFactory: InkSparkle.splashFactory,
              appBarTheme: AppBarTheme(
                backgroundColor: scheme.surface,
                surfaceTintColor: Colors.transparent,
                foregroundColor: scheme.onSurface,
                centerTitle: false,
                elevation: 0,
                titleTextStyle: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              cardTheme: CardThemeData(
                clipBehavior: Clip.antiAlias,
                elevation: 0,
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(borderRadius: radius),
                margin: EdgeInsets.zero,
              ),
              chipTheme: ChipThemeData(
                side: BorderSide.none,
                backgroundColor: scheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: radius, borderSide: BorderSide(color: scheme.primary, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
              floatingActionButtonTheme: FloatingActionButtonThemeData(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              dialogTheme: DialogThemeData(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              ),
              snackBarTheme: SnackBarThemeData(
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              listTileTheme: const ListTileThemeData(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
              ),
              dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5)),
              popupMenuTheme: PopupMenuThemeData(
                color: scheme.surfaceContainerHigh,
                surfaceTintColor: Colors.transparent,
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                textStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w500, fontSize: 15),
              ),
            ),
            home: const LibraryPage(),
          );
        },
      ),
    );
  }
}
