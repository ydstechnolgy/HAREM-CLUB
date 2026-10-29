/// Connexion au projet Supabase et à PowerSync du Harem Club.
/// La clé publique (publishable) peut figurer dans le logiciel :
/// la sécurité des données est assurée par les règles de la base.
/// Ne jamais mettre ici la clé « secret » ni un mot de passe.
class HaremConfig {
  static const supabaseUrl = 'https://udtbszyncufvurwrdhdl.supabase.co';
  static const supabasePublishableKey = 'sb_publishable_TYXHuqnTUI1oqFuA-R-REg_5cJzoNvS';

  /// Adresse de l'instance PowerSync (synchronisation hors ligne).
  static const powersyncUrl = 'https://6ae3c794e9e4b44526cb3d9f.powersync.journeyapps.com';

  /// Les comptes de l'équipe se connectent avec un identifiant : derrière,
  /// Supabase utilise cette adresse interne qui ne reçoit jamais d'e-mail.
  static String emailInterne(String identifiant) =>
      '${identifiant.trim().toLowerCase()}@harem-club.invalid';
}
