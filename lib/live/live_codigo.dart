import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../cloud/cloud_config.dart';

/// Código de 4 dígitos da sessão ao vivo, guardado no Firestore
/// (`sessoes/{codigo}` → IPs e porta de quem criou). Quem entra digita o
/// código em vez do IP; a conexão continua sendo direta pela rede local.
class LiveCodigo {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static String? get _eu =>
      CloudConfig.ligado ? FirebaseAuth.instance.currentUser?.email?.toLowerCase() : null;

  static String? _meu;
  static Timer? _vivo;

  /// Sorteia um código livre e publica. null = sem login/sem internet.
  static Future<String?> publicar({
    required List<String> ips,
    required int porta,
    required String host,
  }) async {
    final eu = _eu;
    if (eu == null || ips.isEmpty) return null;
    final rnd = Random();
    for (var t = 0; t < 8; t++) {
      final c = '${1000 + rnd.nextInt(9000)}';
      try {
        await _db.doc('sessoes/$c').set({
          'ips': ips,
          'porta': porta,
          'host': host,
          'dono': eu,
          'vivoEm': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 8));
        _meu = c;
        // sinal de vida: código parado há mais de 10 min pode ser reaproveitado
        _vivo?.cancel();
        _vivo = Timer.periodic(const Duration(minutes: 3), (_) {
          _db.doc('sessoes/$c').update({'vivoEm': FieldValue.serverTimestamp()}).catchError((_) {});
        });
        return c;
      } on TimeoutException {
        return null; // sem internet: fica só o IP
      } catch (_) {
        // código em uso por outra sessão: sorteia outro
      }
    }
    return null;
  }

  static Future<void> encerrar() async {
    _vivo?.cancel();
    _vivo = null;
    final c = _meu;
    _meu = null;
    if (c == null) return;
    try {
      await _db.doc('sessoes/$c').delete().timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  /// IPs e porta da sessão [codigo], ou null se não existir.
  static Future<({List<String> ips, int porta})?> buscar(String codigo) async {
    if (_eu == null) return null;
    try {
      final d = await _db.doc('sessoes/$codigo').get().timeout(const Duration(seconds: 8));
      final j = d.data();
      if (j == null) return null;
      return (
        ips: ((j['ips'] as List?) ?? const []).cast<String>(),
        porta: (j['porta'] as num?)?.toInt() ?? 47800,
      );
    } catch (_) {
      return null;
    }
  }
}
