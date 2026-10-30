import 'base_locale.dart';

/// Lignes lues dans la base locale.
typedef Lignes = List<Map<String, dynamic>>;

/// Lectures communes de la base locale (elles se mettent à jour toutes seules).
class Requetes {
  Requetes._();

  static Stream<Lignes> soireeOuverte() =>
      db.watch("SELECT * FROM nights WHERE status = 'open' LIMIT 1");

  static Stream<Lignes> categories() =>
      db.watch('SELECT * FROM categories ORDER BY sort_order, name');

  static Stream<Lignes> boissons({bool toutes = false}) => db.watch(
        'SELECT p.*, c.name AS category_name, c.sort_order AS cat_order '
        'FROM products p LEFT JOIN categories c ON c.id = p.category_id '
        '${toutes ? '' : 'WHERE p.active = 1 '}'
        'ORDER BY c.sort_order, p.sort_order, p.name',
      );

  /// Une note avec le nom de sa table et de sa serveuse.
  static Stream<Lignes> note(String tabId) => db.watch(
        'SELECT t.*, ct.name AS table_name, m.display_name AS waitress_name '
        'FROM tabs t LEFT JOIN club_tables ct ON ct.id = t.table_id '
        'LEFT JOIN members m ON m.id = t.waitress_id WHERE t.id = ?',
        parameters: [tabId],
      );

  static Stream<Lignes> boissonsDeLaNote(String tabId) => db.watch(
        'SELECT * FROM tab_items WHERE tab_id = ? '
        "ORDER BY CASE status WHEN 'requested' THEN 0 WHEN 'served' THEN 1 ELSE 2 END, requested_at",
        parameters: [tabId],
      );

  static Stream<Lignes> paiementsDeLaNote(String tabId) =>
      db.watch('SELECT * FROM payments WHERE tab_id = ? ORDER BY created_at', parameters: [tabId]);

  /// Notes de la soirée en cours, avec le nombre de boissons en attente du bar.
  /// [serveuseId] limite aux notes d'une serveuse ; [etats] filtre les états.
  static Stream<Lignes> notesDeLaSoiree({String? serveuseId, List<String>? etats}) {
    final filtres = <String>["t.night_id = (SELECT id FROM nights WHERE status = 'open' LIMIT 1)"];
    final params = <Object?>[];
    if (serveuseId != null) {
      filtres.add('t.waitress_id = ?');
      params.add(serveuseId);
    }
    if (etats != null && etats.isNotEmpty) {
      filtres.add('t.status IN (${List.filled(etats.length, '?').join(', ')})');
      params.addAll(etats);
    }
    return db.watch(
      'SELECT t.*, ct.name AS table_name, m.display_name AS waitress_name, '
      "(SELECT COUNT(*) FROM tab_items i WHERE i.tab_id = t.id AND i.status = 'requested') AS en_attente, "
      "(SELECT COALESCE(SUM(i.quantity * i.unit_price), 0) FROM tab_items i WHERE i.tab_id = t.id AND i.status = 'requested') AS montant_attente "
      'FROM tabs t LEFT JOIN club_tables ct ON ct.id = t.table_id '
      'LEFT JOIN members m ON m.id = t.waitress_id '
      'WHERE ${filtres.join(' AND ')} '
      "ORDER BY CASE t.status WHEN 'to_pay' THEN 0 WHEN 'open' THEN 1 ELSE 2 END, t.opened_at DESC",
      parameters: params,
    );
  }

  /// Tables du club en service, avec « occupee » = 1 si une note y est en cours
  /// (note de cet appareil, ou note d'une collègue signalée par le serveur).
  static Stream<Lignes> tables() => db.watch(
        'SELECT ct.*, CASE WHEN ct.current_tab_id IS NOT NULL OR EXISTS ('
        "SELECT 1 FROM tabs t WHERE t.table_id = ct.id AND t.status IN ('open', 'to_pay')) "
        'THEN 1 ELSE 0 END AS occupee '
        'FROM club_tables ct WHERE ct.active = 1 '
        "ORDER BY CASE ct.zone WHEN 'salle' THEN 0 WHEN 'vip' THEN 1 WHEN 'terrasse' THEN 2 ELSE 3 END, "
        'ct.sort_order, ct.name',
      );

  static Stream<Lignes> reglages() => db.watch('SELECT * FROM settings LIMIT 1');
}
