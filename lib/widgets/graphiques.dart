import 'package:flutter/material.dart';

import '../theme/harem_theme.dart';
import '../utils/format.dart';

/// Une barre de graphique.
class Barre {
  const Barre(this.libelle, this.valeur, {this.detail, this.id, this.choisie = false, this.enCours = false});
  final String libelle;
  final int valeur;
  final String? detail;
  final String? id;
  final bool choisie;
  final bool enCours;
}

/// « 1 250 000 » → « 1,25 M », « 85 000 » → « 85 k ».
String montantCourt(int v) {
  if (v >= 1000000) {
    final m = v / 1000000;
    return '${m.toStringAsFixed(m >= 10 ? 0 : 2).replaceAll('.', ',').replaceAll(RegExp(r',?0+$'), '')} M';
  }
  if (v >= 1000) return '${(v / 1000).round()} k';
  return '$v';
}

/// Barres verticales : le chiffre de chaque soirée, de gauche (ancienne) à droite (récente).
/// Une barre touchée choisit la soirée.
class BarresVerticales extends StatelessWidget {
  const BarresVerticales({super.key, required this.barres, this.onTap, this.hauteur = 200});
  final List<Barre> barres;
  final ValueChanged<Barre>? onTap;
  final double hauteur;

  @override
  Widget build(BuildContext context) {
    final maxi = barres.fold<int>(0, (m, b) => b.valeur > m ? b.valeur : m);
    final moyenne = barres.isEmpty ? 0 : barres.fold<int>(0, (s, b) => s + b.valeur) ~/ barres.length;
    return SizedBox(
      height: hauteur + 52,
      child: LayoutBuilder(builder: (context, c) {
        final largeurBarre = ((c.maxWidth - 8) / (barres.isEmpty ? 1 : barres.length)).clamp(14.0, 64.0);
        return Stack(children: [
          // Ligne de la moyenne
          if (maxi > 0 && moyenne > 0)
            Positioned(
              left: 0,
              right: 0,
              top: 18 + hauteur * (1 - moyenne / maxi),
              child: Row(children: [
                Expanded(child: Container(height: 1, color: HC.orFonce)),
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text('moy. ${montantCourt(moyenne)}', style: const TextStyle(color: HC.orFonce, fontSize: 11)),
                ),
              ]),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final b in barres)
                SizedBox(
                  width: largeurBarre,
                  child: Tooltip(
                    message: '${b.detail ?? b.libelle} : ${fcfa(b.valeur)}',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: onTap == null ? null : () => onTap!(b),
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        if (b.valeur > 0)
                          Text(montantCourt(b.valeur),
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: TextStyle(
                                  fontSize: 10.5, color: b.choisie ? HC.or : HC.gris, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Container(
                          margin: EdgeInsets.symmetric(horizontal: largeurBarre * 0.14),
                          height: maxi == 0 ? 2 : (hauteur * b.valeur / maxi).clamp(2.0, hauteur),
                          decoration: BoxDecoration(
                            color: b.choisie ? HC.or : (b.enCours ? HC.bleu : HC.orFonce),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(b.libelle,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(fontSize: 10.5, color: b.choisie ? HC.or : HC.gris)),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ]);
      }),
    );
  }
}

/// Barres horizontales triées : serveuses, boissons…
class BarresHorizontales extends StatelessWidget {
  const BarresHorizontales({super.key, required this.barres, this.couleur = HC.or, this.formater});
  final List<Barre> barres;
  final Color couleur;

  /// Comment afficher la valeur (par défaut en FCFA).
  final String Function(int)? formater;

  @override
  Widget build(BuildContext context) {
    final maxi = barres.fold<int>(0, (m, b) => b.valeur > m ? b.valeur : m);
    return Column(children: [
      for (final b in barres)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(b.libelle,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              Text((formater ?? fcfa)(b.valeur), style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
            if (b.detail != null)
              Text('${b.detail}', style: const TextStyle(color: HC.gris, fontSize: 12.5)),
            const SizedBox(height: 4),
            LayoutBuilder(
              builder: (context, c) => Stack(children: [
                Container(height: 8, decoration: BoxDecoration(color: HC.surface2, borderRadius: BorderRadius.circular(4))),
                Container(
                  height: 8,
                  width: maxi == 0 ? 0 : c.maxWidth * b.valeur / maxi,
                  decoration: BoxDecoration(color: couleur, borderRadius: BorderRadius.circular(4)),
                ),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

/// Une seule barre partagée en deux (ex. espèces / Mobile Money).
class BarrePartagee extends StatelessWidget {
  const BarrePartagee({super.key, required this.gauche, required this.droite});
  final Barre gauche;
  final Barre droite;

  @override
  Widget build(BuildContext context) {
    final total = gauche.valeur + droite.valeur;
    if (total == 0) return const SizedBox.shrink();
    final g = (gauche.valeur * 1000 ~/ total).clamp(0, 1000);
    final pc = (gauche.valeur * 100 / total).round();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 14,
          child: Row(children: [
            if (g > 0) Expanded(flex: g, child: Container(color: HC.or)),
            if (g < 1000) Expanded(flex: 1000 - g, child: Container(color: HC.bleu)),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 20, runSpacing: 6, children: [
        _legende(HC.or, '${gauche.libelle} $pc %'),
        _legende(HC.bleu, '${droite.libelle} ${100 - pc} %'),
      ]),
    ]);
  }

  Widget _legende(Color c, String texte) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, color: c),
        const SizedBox(width: 6),
        Text(texte, style: const TextStyle(fontSize: 12.5)),
      ]);
}
