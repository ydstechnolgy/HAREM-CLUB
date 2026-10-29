import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/base_locale.dart';
import '../../data/membre.dart';
import '../../data/requetes.dart';
import '../../theme/harem_theme.dart';
import '../../widgets/commun.dart';

/// Comptes de l'équipe (patron seulement) : il faut internet.
class EquipePage extends StatelessWidget {
  const EquipePage({super.key, required this.membre});
  final Membre membre;

  static final _rpc = Supabase.instance.client;

  static String _role(String? r) => switch (r) {
        'patron' => 'Patron',
        'gerant' => 'Gérant (caissier)',
        _ => 'Serveuse',
      };

  Future<void> _creer(BuildContext context) async {
    final nom = TextEditingController();
    final identifiant = TextEditingController();
    final pin = TextEditingController();
    final tel = TextEditingController();
    var role = 'serveuse';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Nouveau compte'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'serveuse', label: Text('Serveuse')),
                    ButtonSegment(value: 'gerant', label: Text('Gérant')),
                    ButtonSegment(value: 'patron', label: Text('Patron')),
                  ],
                  selected: {role},
                  onSelectionChanged: (s) => set(() => role = s.first),
                ),
                const SizedBox(height: 12),
                TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom affiché (ex. Ama)')),
                const SizedBox(height: 12),
                TextField(
                  controller: identifiant,
                  autocorrect: false,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._-]'))],
                  decoration: const InputDecoration(
                      labelText: 'Identifiant de connexion', helperText: 'Lettres et chiffres, sans espace (ex. ama)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pin,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Code PIN (6 chiffres)'),
                ),
                TextField(controller: tel, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone (facultatif)')),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Créer le compte')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final fait = await tenter(context, () async {
      await _rpc.rpc('create_member', params: {
        'p_login': identifiant.text.trim().toLowerCase(),
        'p_pin': pin.text.trim(),
        'p_display_name': nom.text.trim(),
        'p_role': role,
        'p_phone': tel.text.trim().isEmpty ? null : tel.text.trim(),
      });
    });
    if (fait && context.mounted) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Compte créé'),
          content: Text('Donnez ces informations à ${nom.text.trim()} :\n\n'
              'Identifiant : ${identifiant.text.trim().toLowerCase()}\n'
              'Code PIN : ${pin.text.trim()}\n\n'
              'Elle se connecte dans l\'application Harem Club.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    }
  }

  Future<void> _actions(BuildContext context, Map<String, dynamic> m) async {
    final actif = ouiNon(m['active']);
    final choix = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('${m['display_name']}'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'pin'), child: const Text('Changer le code PIN')),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'role'), child: const Text('Modifier le nom ou le rôle')),
          if (m['id'] != membre.id)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'actif'),
              child: Text(actif ? 'Désactiver le compte' : 'Réactiver le compte',
                  style: TextStyle(color: actif ? HC.rouge : HC.vert)),
            ),
        ],
      ),
    );
    if (choix == null || !context.mounted) return;
    switch (choix) {
      case 'pin':
        final pin = await demanderTexte(context, 'Nouveau code PIN', label: '6 chiffres');
        if (pin == null || pin.isEmpty || !context.mounted) return;
        await tenter(context, () => _rpc.rpc('set_member_pin', params: {'p_member_id': m['id'], 'p_pin': pin}),
            succes: 'Code PIN changé.');
      case 'role':
        final nom = TextEditingController(text: '${m['display_name']}');
        var role = '${m['role']}';
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, set) => AlertDialog(
              title: const Text('Modifier le compte'),
              content: SizedBox(
                width: 420,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom affiché')),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'serveuse', label: Text('Serveuse')),
                      ButtonSegment(value: 'gerant', label: Text('Gérant')),
                      ButtonSegment(value: 'patron', label: Text('Patron')),
                    ],
                    selected: {role},
                    onSelectionChanged: (s) => set(() => role = s.first),
                  ),
                ]),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
              ],
            ),
          ),
        );
        if (ok == true && context.mounted) {
          await tenter(context,
              () => _rpc.rpc('update_member',
                  params: {'p_member_id': m['id'], 'p_display_name': nom.text.trim(), 'p_role': role, 'p_phone': m['phone']}),
              succes: 'Compte modifié.');
        }
      case 'actif':
        final ok = await confirmer(
          context,
          actif ? 'Désactiver ${m['display_name']} ?' : 'Réactiver ${m['display_name']} ?',
          actif ? 'Cette personne ne pourra plus se connecter. Son historique est gardé.' : 'Elle pourra à nouveau se connecter.',
          bouton: actif ? 'Désactiver' : 'Réactiver',
          danger: actif,
        );
        if (ok && context.mounted) {
          await tenter(context, () => _rpc.rpc('set_member_active', params: {'p_member_id': m['id'], 'p_active': !actif}));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _creer(context),
        icon: const Icon(Icons.person_add),
        label: const Text('Nouveau compte'),
      ),
      body: StreamBuilder<Lignes>(
        stream: db.watch(
            "SELECT * FROM members ORDER BY active DESC, CASE role WHEN 'patron' THEN 0 WHEN 'gerant' THEN 1 ELSE 2 END, display_name"),
        builder: (context, snap) {
          final membres = snap.data ?? const [];
          return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
            const Text('Créer un compte, changer un code PIN ou désactiver un compte demande internet.',
                style: TextStyle(color: HC.gris)),
            const SizedBox(height: 8),
            for (final m in membres)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: ouiNon(m['active']) ? HC.fondOr : HC.surface2,
                    child: Text('${m['display_name']}'.isEmpty ? '?' : '${m['display_name']}'.substring(0, 1).toUpperCase(),
                        style: const TextStyle(color: HC.or, fontWeight: FontWeight.w800)),
                  ),
                  title: Text('${m['display_name']}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: ouiNon(m['active']) ? HC.texte : HC.gris)),
                  subtitle: Text('${_role(m['role'] as String?)} · identifiant : ${m['login']}'
                      '${ouiNon(m['active']) ? '' : ' · désactivé'}'),
                  trailing: const Icon(Icons.more_vert, color: HC.gris),
                  onTap: () => _actions(context, m),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
