import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:powersync/powersync.dart';
import 'package:sqlite_async/sqlite_async.dart' show SqliteWriteContext;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../services/appareil.dart' as appareil;

/// Base de données locale du Harem Club (sur le PC ou le téléphone).
///
/// Le logiciel lit et écrit toujours ici, même sans internet.
/// PowerSync envoie les changements à Supabase dès que la connexion revient,
/// et rapatrie ce qui a été fait sur les autres appareils.
late final PowerSyncDatabase db;

const schemaLocal = Schema([
  Table('settings', [
    Column.text('club'),
    Column.text('club_name'),
    Column.text('phone'),
    Column.text('ticket_header'),
    Column.text('ticket_footer'),
    Column.integer('night_start_hour'),
    Column.text('updated_at'),
  ]),
  Table('members', [
    Column.text('club'),
    Column.text('user_id'),
    Column.text('login'),
    Column.text('role'),
    Column.text('display_name'),
    Column.text('phone'),
    Column.integer('active'),
    Column.text('created_at'),
  ]),
  Table('club_tables', [
    Column.text('club'),
    Column.text('name'),
    Column.text('zone'),
    Column.integer('is_fixed'),
    Column.integer('active'),
    Column.integer('sort_order'),
    Column.text('created_by'),
    Column.text('created_at'),
  ]),
  Table('categories', [
    Column.text('club'),
    Column.text('name'),
    Column.integer('sort_order'),
    Column.text('created_at'),
  ]),
  Table('products', [
    Column.text('club'),
    Column.text('category_id'),
    Column.text('name'),
    Column.integer('sale_price'),
    Column.integer('track_stock'),
    Column.integer('min_stock'),
    Column.integer('active'),
    Column.integer('sort_order'),
    Column.text('created_at'),
    Column.text('updated_at'),
  ], indexes: [
    Index('categorie', [IndexedColumn('category_id')]),
  ]),
  Table('suppliers', [
    Column.text('club'),
    Column.text('name'),
    Column.text('phone'),
    Column.text('note'),
    Column.integer('active'),
    Column.text('created_at'),
  ]),
  Table('nights', [
    Column.text('club'),
    Column.text('status'),
    Column.text('opened_by'),
    Column.text('opened_at'),
    Column.integer('opening_float'),
    Column.text('closed_by'),
    Column.text('closed_at'),
    Column.integer('expected_cash'),
    Column.integer('expected_momo'),
    Column.integer('counted_cash'),
    Column.integer('counted_momo'),
    Column.integer('difference_cash'),
    Column.integer('difference_momo'),
    Column.text('note'),
  ]),
  Table('tabs', [
    Column.text('club'),
    Column.text('night_id'),
    Column.text('table_id'),
    Column.text('waitress_id'),
    Column.text('status'),
    Column.integer('ticket_number'),
    Column.integer('total'),
    Column.integer('paid_amount'),
    Column.text('opened_at'),
    Column.text('requested_at'),
    Column.text('paid_at'),
    Column.text('cashier_id'),
    Column.text('cancelled_by'),
    Column.text('cancel_reason'),
  ], indexes: [
    Index('soiree', [IndexedColumn('night_id')]),
    Index('serveuse', [IndexedColumn('waitress_id')]),
  ]),
  Table('tab_items', [
    Column.text('club'),
    Column.text('tab_id'),
    Column.text('product_id'),
    Column.text('product_name'),
    Column.integer('quantity'),
    Column.integer('unit_price'),
    Column.text('status'),
    Column.text('requested_at'),
    Column.text('requested_by'),
    Column.text('served_by'),
    Column.text('served_at'),
    Column.text('removed_by'),
    Column.text('removed_at'),
    Column.text('removed_reason'),
  ], indexes: [
    Index('note', [IndexedColumn('tab_id')]),
    Index('etat', [IndexedColumn('status')]),
  ]),
  Table('payments', [
    Column.text('club'),
    Column.text('tab_id'),
    Column.text('night_id'),
    Column.text('method'),
    Column.integer('amount'),
    Column.text('received_by'),
    Column.text('created_at'),
  ], indexes: [
    Index('note', [IndexedColumn('tab_id')]),
  ]),
  Table('cash_movements', [
    Column.text('club'),
    Column.text('night_id'),
    Column.text('type'),
    Column.integer('amount'),
    Column.text('reason'),
    Column.text('member_id'),
    Column.text('created_at'),
  ]),
  Table('expenses', [
    Column.text('club'),
    Column.text('night_id'),
    Column.text('label'),
    Column.text('category'),
    Column.integer('amount'),
    Column.text('method'),
    Column.integer('from_till'),
    Column.text('supplier_id'),
    Column.text('member_id'),
    Column.text('created_at'),
  ]),
  Table('stock_entries', [
    Column.text('club'),
    Column.text('product_id'),
    Column.integer('quantity'),
    Column.text('supplier_id'),
    Column.text('note'),
    Column.text('member_id'),
    Column.text('created_at'),
  ]),
  Table('stock_movements', [
    Column.text('club'),
    Column.text('product_id'),
    Column.text('type'),
    Column.integer('quantity'),
    Column.text('tab_item_id'),
    Column.text('entry_id'),
    Column.text('inventory_id'),
    Column.text('reason'),
    Column.text('member_id'),
    Column.text('created_at'),
  ], indexes: [
    Index('produit', [IndexedColumn('product_id')]),
  ]),
  Table('inventories', [
    Column.text('club'),
    Column.integer('nb_products'),
    Column.integer('nb_ecarts'),
    Column.text('note'),
    Column.text('member_id'),
    Column.text('created_at'),
  ]),

  /// Opérations à rejouer sur le serveur (fonctions Supabase) : envoyées puis effacées.
  Table.insertOnly('operations', [
    Column.text('type'),
    Column.text('payload'),
    Column.text('created_at'),
  ]),

  /// Envois refusés par le serveur, gardés pour les montrer et ne rien perdre.
  Table.localOnly('envois_refuses', [
    Column.text('type'),
    Column.text('payload'),
    Column.text('erreur'),
    Column.text('created_at'),
  ]),
]);

/// Fonctions du serveur que l'appareil a le droit de rejouer (script 03).
const _fonctionsAutorisees = {
  'open_night', 'close_night', 'create_table', 'open_tab', 'add_items', 'cancel_request',
  'request_payment', 'reopen_tab', 'serve_items', 'refuse_items', 'remove_item',
  'record_payment', 'cancel_tab', 'add_cash_movement', 'record_expense', 'receive_stock',
  'adjust_stock', 'record_inventory',
};

/// Tables écrites localement en avance (affichage immédiat) mais enregistrées
/// sur le serveur par une opération : leurs changements ne sont pas envoyés tels quels.
const _tablesViaOperations = {
  'nights', 'tabs', 'tab_items', 'payments', 'cash_movements', 'expenses', 'stock_entries',
  'stock_movements', 'inventories', 'members',
};

/// Colonnes oui/non : SQLite les stocke en 0/1, Supabase attend true/false.
const _colonnesOuiNon = {'active', 'track_stock', 'is_fixed', 'from_till'};

/// Erreurs définitives : renvoyer la même donnée ne servira à rien.
final _erreursDefinitives = [
  RegExp(r'^22...$'), // donnée invalide
  RegExp(r'^23...$'), // contrainte non respectée
  RegExp(r'^42...$'), // accès refusé, fonction inconnue
  RegExp(r'^P0001$'), // refus du club (ex. « Cette table a déjà une note en cours »)
  RegExp(r'^PGRST'), // demande mal formée
];

/// Date et heure au format de la base.
String maintenantIso() => DateTime.now().toUtc().toIso8601String();

/// Nouvel identifiant unique, créé sans internet.
Future<String> nouvelId() async => (await db.get('SELECT uuid() AS id'))['id'] as String;

/// Vrai pour les colonnes oui/non, qu'elles arrivent en 1/0 ou en true/false.
bool ouiNon(Object? v) => v == 1 || v == true || v == 'true' || v == '1';

/// Nombre entier lu dans une ligne (0 si vide).
int entier(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0);

/// Ajoute une opération à envoyer au serveur (dans une transaction en cours).
Future<void> ajouterOperation(SqliteWriteContext tx, String fonction, Map<String, dynamic> params) async {
  assert(_fonctionsAutorisees.contains(fonction));
  await tx.execute(
    'INSERT INTO operations (id, type, payload, created_at) VALUES (uuid(), ?, ?, ?)',
    [fonction, jsonEncode(params), maintenantIso()],
  );
}

class _ConnecteurSupabase extends PowerSyncBackendConnector {
  Future<void>? _rafraichissement;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    await _rafraichissement;
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return null;
    return PowerSyncCredentials(
      endpoint: HaremConfig.powersyncUrl,
      token: session.accessToken,
      userId: session.user.id,
      expiresAt: session.expiresAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000),
    );
  }

  @override
  void invalidateCredentials() {
    _rafraichissement = Supabase.instance.client.auth
        .refreshSession()
        .timeout(const Duration(seconds: 5))
        .then((_) => null, onError: (_) => null);
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final client = Supabase.instance.client;
    while (true) {
      final transaction = await database.getNextCrudTransaction();
      if (transaction == null) return;

      for (final op in transaction.crud) {
        try {
          await _envoyer(client, op);
        } on PostgrestException catch (e) {
          final code = e.code;
          if (code != null && _erreursDefinitives.any((re) => re.hasMatch(code))) {
            // Refus définitif : on garde une trace locale au lieu de bloquer la file.
            await database.execute(
              'INSERT INTO envois_refuses (id, type, payload, erreur, created_at) '
              'VALUES (uuid(), ?, ?, ?, ?)',
              [
                op.table == 'operations' ? (op.opData?['type'] ?? op.table) : op.table,
                jsonEncode(op.opData),
                e.message,
                maintenantIso(),
              ],
            );
            debugPrint('Harem Club : envoi refusé (${op.table}) : ${e.message}');
          } else {
            rethrow; // erreur passagère (réseau…) : PowerSync réessaiera plus tard
          }
        }
      }
      await transaction.complete();
    }
  }

  Future<void> _envoyer(SupabaseClient client, CrudEntry op) async {
    if (op.table == 'operations') {
      final fonction = op.opData?['type'] as String?;
      if (fonction == null || !_fonctionsAutorisees.contains(fonction)) {
        debugPrint('Harem Club : opération inconnue $fonction');
        return;
      }
      final params = jsonDecode(op.opData?['payload'] as String? ?? '{}') as Map<String, dynamic>;
      await client.rpc(fonction, params: params);
      return;
    }
    if (_tablesViaOperations.contains(op.table)) return;
    // Une nouvelle table du club passe par la fonction create_table ; seules
    // les modifications (renommer, retirer) sont envoyées directement.
    if (op.table == 'club_tables' && op.op == UpdateType.put) return;

    final table = client.from(op.table);
    final donnees = <String, dynamic>{
      for (final e in (op.opData ?? const <String, dynamic>{}).entries)
        e.key: _colonnesOuiNon.contains(e.key) && e.value != null ? ouiNon(e.value) : e.value,
    };
    switch (op.op) {
      case UpdateType.put:
        await table.upsert({...donnees, 'id': op.id});
      case UpdateType.patch:
        await table.update(donnees).eq('id', op.id);
      case UpdateType.delete:
        await table.delete().eq('id', op.id);
    }
  }
}

_ConnecteurSupabase? _connecteur;

void _connecter() {
  _connecteur = _ConnecteurSupabase();
  db.connect(connector: _connecteur!);
}

/// Ouvre la base locale et la relie à la session Supabase.
Future<void> ouvrirBaseLocale() async {
  db = PowerSyncDatabase(schema: schemaLocal, path: await appareil.cheminBaseLocale('harem_club.db'));
  await db.initialize();

  final auth = Supabase.instance.client.auth;
  if (auth.currentSession != null) _connecter();

  auth.onAuthStateChange.listen((data) async {
    switch (data.event) {
      case AuthChangeEvent.signedIn:
        _connecter();
      case AuthChangeEvent.signedOut:
        _connecteur = null;
        await db.disconnect();
      case AuthChangeEvent.tokenRefreshed:
        _connecteur?.prefetchCredentials();
      default:
        break;
    }
  });
}

/// Attend que les données soient arrivées au moins une fois sur cet appareil.
Future<void> attendrePremiereSynchro() async {
  if (db.currentStatus.hasSynced == true) return;
  try {
    await db.waitForFirstSync().timeout(const Duration(seconds: 45));
  } on TimeoutException {
    throw Exception(
      'Première synchronisation impossible. Connectez cet appareil au Wi-Fi du club '
      'une première fois pour télécharger le menu et les tables.',
    );
  }
}

/// Nombre de changements faits ici et pas encore envoyés au serveur.
Future<int> changementsEnAttente() async => (await db.getUploadQueueStats()).count;

/// Déconnexion complète : refusée si des changements n'ont pas encore été envoyés.
/// Renvoie un message d'explication si la déconnexion n'a pas eu lieu.
Future<String?> seDeconnecter() async {
  final enAttente = await changementsEnAttente();
  if (enAttente > 0) {
    return '$enAttente changement${enAttente > 1 ? 's' : ''} pas encore envoyé${enAttente > 1 ? 's' : ''} '
        'au serveur. Reconnectez le Wi-Fi et patientez quelques secondes avant de vous déconnecter.';
  }
  await Supabase.instance.client.auth.signOut();
  await db.disconnectAndClear();
  return null;
}
