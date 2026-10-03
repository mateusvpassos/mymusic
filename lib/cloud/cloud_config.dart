import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

/// Liga o Firebase: o projeto de verdade (firebase_options.dart) ou, nos
/// testes, o emulador local (`--dart-define=MYMUSIC_EMU=10.0.2.2`).
class CloudConfig {
  static const emuHost = String.fromEnvironment('MYMUSIC_EMU');
  static bool get emulador => emuHost.isNotEmpty;

  /// Client OAuth "Web" do projeto Google — o login do Android pede o
  /// idToken com ele como público.
  static const webClientId =
      '333951307134-ttuhelsl1nfrbrfsd21i3a783falt8s9.apps.googleusercontent.com';

  static FirebaseOptions? get options => emulador
      ? const FirebaseOptions(
          apiKey: 'demo-key',
          appId: '1:1:android:1',
          messagingSenderId: '1',
          projectId: 'demo-mymusic',
        )
      : firebaseAndroid;

  static bool ligado = false;

  static Future<bool> init() async {
    final o = options;
    if (o == null) return false;
    try {
      await Firebase.initializeApp(options: o);
      if (emulador) {
        FirebaseFirestore.instance.useFirestoreEmulator(emuHost, 8188);
        await FirebaseAuth.instance.useAuthEmulator(emuHost, 9099);
      }
      ligado = true;
    } catch (_) {
      ligado = false;
    }
    return ligado;
  }
}
