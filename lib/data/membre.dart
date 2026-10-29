import 'package:supabase_flutter/supabase_flutter.dart';

import 'base_locale.dart';

/// La personne connectée sur cet appareil.
class Membre {
  Membre({required this.id, required this.login, required this.role, required this.nom});

  final String id;
  final String login;
  final String role; // patron, gerant, serveuse
  final String nom;

  bool get estPatron => role == 'patron';
  bool get estStaff => role == 'patron' || role == 'gerant';
  bool get estServeuse => role == 'serveuse';

  String get libelleRole => switch (role) {
        'patron' => 'Patron',
        'gerant' => 'Gérant',
        _ => 'Serveuse',
      };

  static Membre _depuis(Map<String, dynamic> r) => Membre(
        id: r['id'] as String,
        login: (r['login'] ?? '') as String,
        role: (r['role'] ?? 'serveuse') as String,
        nom: (r['display_name'] ?? '') as String,
      );

  /// Lit la personne connectée dans la base locale (null si son compte n'existe pas ou est désactivé).
  static Future<Membre?> charger() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return null;
    final r = await db.getOptional(
        'SELECT * FROM members WHERE user_id = ? AND active = 1 LIMIT 1', [uid]);
    return r == null ? null : _depuis(r);
  }
}
