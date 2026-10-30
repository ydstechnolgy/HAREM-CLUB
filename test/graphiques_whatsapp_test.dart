import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harem_club/services/recu.dart';
import 'package:harem_club/theme/harem_theme.dart';
import 'package:harem_club/widgets/graphiques.dart';

void main() {
  test('numéros WhatsApp', () {
    expect(Recu.numeroWhatsApp('90 12 34 56'), '22890123456');
    expect(Recu.numeroWhatsApp('+228 90 12 34 56'), '22890123456');
    expect(Recu.numeroWhatsApp('00229 97 00 00 00'), '22997000000');
    expect(Recu.numeroWhatsApp('9012'), isNull);
  });

  test('montants courts', () {
    expect(montantCourt(850), '850');
    expect(montantCourt(85000), '85 k');
    expect(montantCourt(1250000), '1,25 M');
    expect(montantCourt(2000000), '2 M');
  });

  for (final (nom, taille) in [('téléphone', const Size(390, 844)), ('PC', const Size(1366, 768))]) {
    testWidgets('graphiques sur $nom', (tester) async {
      tester.view.physicalSize = taille;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String? touche;
      await tester.pumpWidget(MaterialApp(
        theme: HaremTheme.theme(),
        home: Scaffold(
          body: ListView(padding: const EdgeInsets.all(16), children: [
            BarresVerticales(
              barres: [
                for (var i = 0; i < 14; i++)
                  Barre('sam ${i + 1}', i * 137000, id: 'n$i', choisie: i == 13, enCours: i == 13),
              ],
              onTap: (b) => touche = b.id,
            ),
            const BarresHorizontales(barres: [
              Barre('Ama la serveuse au très long prénom', 450000, detail: '12 note(s) · 40 boisson(s)'),
              Barre('Esi', 120000),
            ]),
            const BarrePartagee(gauche: Barre('Espèces', 300000), droite: Barre('Mobile Money', 100000)),
            const BarrePartagee(gauche: Barre('Espèces', 0), droite: Barre('Mobile Money', 0)),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('sam 14'));
      expect(touche, 'n13');
      expect(find.text('Espèces 75 %'), findsOneWidget);
    });
  }
}
