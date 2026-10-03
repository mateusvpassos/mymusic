import 'package:firebase_core/firebase_core.dart';

/// Configuração do projeto Firebase do ministério (console do Firebase →
/// Configurações do projeto → Seus apps → Android). Não é segredo: o acesso
/// é controlado pelas regras em firebase/firestore.rules.
///
/// null = nuvem ainda não configurada (o app funciona só com o Drive).
const FirebaseOptions? firebaseAndroid = null;
