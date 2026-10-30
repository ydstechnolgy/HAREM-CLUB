import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/harem_theme.dart';

/// Icône du menu avec un petit nombre rouge (demandes au bar, notes à encaisser).
/// Taille fixe : ne déborde jamais, sur téléphone comme sur PC.
class IconeCompteur extends StatelessWidget {
  const IconeCompteur({super.key, required this.icone, this.compte});
  final IconData icone;

  /// Nombre à afficher ; null = icône simple.
  final ValueListenable<int>? compte;

  @override
  Widget build(BuildContext context) {
    final c = compte;
    if (c == null) return SizedBox(width: 32, height: 26, child: Icon(icone, size: 24));
    return ValueListenableBuilder<int>(
      valueListenable: c,
      builder: (context, n, _) => SizedBox(
        width: 32,
        height: 26,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(left: 4, top: 1, child: Icon(icone, size: 24)),
          if (n > 0)
            Positioned(
              right: -6,
              top: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(color: HC.rouge, borderRadius: BorderRadius.circular(9)),
                alignment: Alignment.center,
                child: Text(n > 99 ? '99+' : '$n',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, height: 1)),
              ),
            ),
        ]),
      ),
    );
  }
}
