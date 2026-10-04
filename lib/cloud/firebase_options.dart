import 'package:firebase_core/firebase_core.dart';

/// Configuração do projeto Firebase "cifras-779b6" (console do Firebase →
/// Configurações do projeto → Seus apps → Android). Não é segredo: o acesso
/// é controlado pelas regras em firebase/firestore.rules.
///
/// null = nuvem ainda não configurada (o app funciona só com o Drive).
// ignore: unnecessary_nullable_for_final_variable_declarations
const FirebaseOptions? firebaseAndroid = FirebaseOptions(
  apiKey: 'AIzaSyDePucmEzSntxSNjVjT20nfcR4OxHIi-JA',
  appId: '1:167404504785:android:355a67d88867eb5e8467f0',
  messagingSenderId: '167404504785',
  projectId: 'cifras-779b6',
  storageBucket: 'cifras-779b6.firebasestorage.app',
);

/// null até registrar o app iOS no mesmo projeto Firebase
/// (bundle `com.mvini.mymusic`) e colar aqui o bloco do console.
const FirebaseOptions? firebaseIos = null;
