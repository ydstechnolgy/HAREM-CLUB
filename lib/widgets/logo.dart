import 'package:flutter/material.dart';

import '../theme/harem_theme.dart';

/// Nom du club, en or, comme sur le logo.
class Logo extends StatelessWidget {
  const Logo({super.key, this.taille = 40, this.slogan = true});
  final double taille;
  final bool slogan;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star, color: HC.or, size: taille * 0.45),
        Text('HAREM',
            style: TextStyle(
                fontFamily: 'serif',
                fontSize: taille,
                fontWeight: FontWeight.w800,
                letterSpacing: taille * 0.12,
                color: HC.or,
                height: 1.1)),
        Text('— CLUB —',
            style: TextStyle(fontSize: taille * 0.34, letterSpacing: taille * 0.2, color: HC.or, fontWeight: FontWeight.w700)),
        if (slogan) ...[
          SizedBox(height: taille * 0.2),
          Text('LA SKINNY EST DANS LA VILLE',
              style: TextStyle(fontSize: taille * 0.22, letterSpacing: 1.5, color: HC.orFonce, fontWeight: FontWeight.w700)),
        ],
      ],
    );
  }
}
