import 'package:supabase_flutter/supabase_flutter.dart';

/// Traduit les erreurs techniques en messages clairs, en français.
String messageErreur(Object erreur) {
  if (erreur is AuthException) {
    final m = erreur.message.toLowerCase();
    if (m.contains('invalid login credentials') || m.contains('invalid_credentials')) {
      return 'Identifiant ou code PIN incorrect.';
    }
    if (m.contains('rate limit') || m.contains('too many')) {
      return 'Trop de tentatives. Patientez quelques minutes.';
    }
    if (m.contains('socket') || m.contains('network') || m.contains('failed host lookup')) {
      return 'Pas de connexion internet. Connectez-vous au Wi-Fi du club puis réessayez.';
    }
    return 'Connexion impossible : ${erreur.message}';
  }
  if (erreur is PostgrestException) {
    if (erreur.message.contains('Could not find the function')) {
      return 'La base de données n\'est pas à jour : un script SUPABASE n\'a pas été lancé.';
    }
    // Messages écrits dans les scripts SQL du club (raise exception) : affichés tels quels.
    if (erreur.code == 'P0001') return erreur.message;
    return 'Erreur de la base de données : ${erreur.message}';
  }
  final texte = erreur.toString().toLowerCase();
  if (texte.contains('socket') || texte.contains('failed host lookup') ||
      texte.contains('network') || texte.contains('clientexception')) {
    return 'Pas de connexion internet. Connectez-vous au Wi-Fi du club puis réessayez.';
  }
  final brut = erreur.toString();
  if (erreur is Exception && brut.startsWith('Exception: ')) {
    return brut.substring('Exception: '.length);
  }
  return 'Une erreur est survenue. Réessayez.';
}
