// Le menu de gestion (tiroir du téléphone, barre latérale du PC) avec les compteurs rouges.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harem_club/theme/harem_theme.dart';
import 'package:harem_club/widgets/icone_compteur.dart';

Widget _app(Widget home) => MaterialApp(theme: HaremTheme.theme(), home: home);

void main() {
  final bar = ValueNotifier<int>(3);
  final caisse = ValueNotifier<int>(0);

  List<(String, IconData, ValueNotifier<int>?)> rubriques() => [
        ('Bar', Icons.local_bar, bar),
        ('Encaisser', Icons.point_of_sale, caisse),
        ('Tables en cours', Icons.table_restaurant, null),
      ];

  testWidgets('tiroir du téléphone', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(Scaffold(
      appBar: AppBar(title: const Text('Bar')),
      drawer: Drawer(
        backgroundColor: HC.surface,
        child: ListView(children: [
          for (final (i, r) in rubriques().indexed)
            ListTile(
              leading: IconeCompteur(icone: r.$2, compte: r.$3),
              title: Text(r.$1),
              selected: i == 0,
              selectedColor: HC.or,
            ),
        ]),
      ),
    )));
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // L'icône garde sa petite taille et le titre a toute la place.
    expect(tester.getSize(find.byType(IconeCompteur).first).width, lessThanOrEqualTo(40));
    expect(tester.getSize(find.text('Encaisser')).width, greaterThan(60));
    expect(find.text('3'), findsOneWidget);
    // Le compteur se met à jour tout seul.
    caisse.value = 2;
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('barre latérale du PC', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(Scaffold(
      body: Row(children: [
        NavigationRail(
          extended: true,
          minExtendedWidth: 220,
          selectedIndex: 0,
          destinations: [
            for (final r in rubriques())
              NavigationRailDestination(icon: IconeCompteur(icone: r.$2, compte: r.$3), label: Text(r.$1)),
          ],
        ),
        const Expanded(child: SizedBox()),
      ]),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Tables en cours'), findsOneWidget);
  });
}
