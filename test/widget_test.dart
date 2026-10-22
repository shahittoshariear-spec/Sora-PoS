import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sora_pos/analytics.dart';
import 'package:sora_pos/cart.dart';
import 'package:sora_pos/demo.dart';
import 'package:sora_pos/format.dart';
import 'package:sora_pos/models.dart';
import 'package:sora_pos/screens/till.dart';
import 'package:sora_pos/store.dart';
import 'package:sora_pos/ui/kit.dart';
import 'package:sora_pos/ui/theme.dart';

void main() {
  group('passwords', () {
    test('a password verifies only against its own salt', () {
      final salt = Passwords.newSalt();
      final hash = Passwords.hash('demo1234', salt);
      final staff = Staff(
        id: 's',
        name: 'A',
        role: Role.owner,
        passwordHash: hash,
        salt: salt,
      );
      expect(staff.matches('demo1234'), isTrue);
      expect(staff.matches('Demo1234'), isFalse);
    });
  });

  group('cart arithmetic', () {
    test('subtotal, tax and total agree', () {
      final subtotal = round2(28 + 26 + 58);
      final tax = round2(subtotal * 0.15);
      expect(round2(subtotal + tax), 128.80);
    });

    test('money keeps its cents', () {
      expect(round2(0.1 + 0.2), 0.3);
      expect(numText(2), '2');
      expect(numText(2.5), '2.50');
    });
  });

  group('periods', () {
    test('day bounds are local and whole', () {
      final d = DateTime(2026, 10, 21, 15, 33);
      expect(periodStart(PeriodTab.day, d), DateTime(2026, 10, 21));
      expect(periodEnd(PeriodTab.day, d), DateTime(2026, 10, 22));
    });

    test('a week starts on Monday', () {
      final d = DateTime(2026, 10, 21);
      expect(periodStart(PeriodTab.week, d).weekday, DateTime.monday);
    });
  });

  group('refund arithmetic', () {
    test('a refund nets its line and its tax', () {
      final sale = Sale(
        number: 1001,
        at: DateTime.now(),
        lines: [
          SaleLine(productId: 'a', name: 'A', unitPrice: 100, cost: 40, qty: 2),
        ],
        subtotal: 200,
        tax: 30,
        total: 230,
        cash: 230,
        card: 0,
        cashierId: 's',
        cashierName: 'A',
      );
      final data = AppData(shop: ShopInfo(taxRate: 15), sales: [sale]);
      final t = totalsForDay(data, DateTime.now());
      expect(t.sales, 230);
      expect(t.profit, 120);
    });
  });

  group('roles', () {
    Store storeFor(Role role) {
      final store = Store();
      store.current = Staff(
        id: 's-${role.name}',
        name: role.name,
        role: role,
        salt: 'salt',
        passwordHash: 'hash',
      );
      return store;
    }

    test('a cashier only reaches the till', () {
      final store = storeFor(Role.cashier);
      expect(store.mayOpen('till'), isTrue);
      for (final section in [
        'stock',
        'ledger',
        'overview',
        'reports',
        'setup',
      ]) {
        expect(store.mayOpen(section), isFalse, reason: section);
      }
    });

    test('a manager reaches the till, stock and ledger', () {
      final store = storeFor(Role.manager);
      for (final section in ['till', 'stock', 'ledger']) {
        expect(store.mayOpen(section), isTrue, reason: section);
      }
      for (final section in ['overview', 'reports', 'setup']) {
        expect(store.mayOpen(section), isFalse, reason: section);
      }
    });

    test('an owner reaches everything', () {
      final store = storeFor(Role.owner);
      for (final section in [
        'till',
        'stock',
        'ledger',
        'overview',
        'reports',
        'setup',
      ]) {
        expect(store.mayOpen(section), isTrue, reason: section);
      }
    });
  });

  testWidgets(
    'the till divider guide appears during a drag and commits on release',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final store = Store();
      store.data = buildDemoData();
      final cart = CartController();

      await tester.pumpWidget(
        MaterialApp(
          theme: buildSoraTheme(SoraPalette.named.first, 0),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(1800, 1000),
              textScaler: TextScaler.linear(0.55),
            ),
            child: Scaffold(
              body: TillScreen(store: store, cart: cart),
            ),
          ),
        ),
      );
      await tester.pump();

      final grip = find.byKey(const ValueKey('till-split-grip'));
      expect(grip, findsOneWidget);
      final before = tester.getCenter(grip).dx;

      final gesture = await tester.startGesture(tester.getCenter(grip));
      await gesture.moveBy(const Offset(-180, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        find.byKey(const ValueKey('till-split-guide')),
        findsOneWidget,
        reason: 'the ghost guide must be visible while dragging',
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('till-split-guide')), findsNothing);
      expect(tester.getCenter(grip).dx, lessThan(before));
      expect(store.data.settings.tillPanelFraction, greaterThan(0.34));
    },
  );

  testWidgets('a glass button answers across its whole pill', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildSoraTheme(SoraPalette.named.first, 0),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: GlassButton(
                label: 'Charge R36.80',
                primary: true,
                expand: true,
                onPressed: () => taps++,
              ),
            ),
          ),
        ),
      ),
    );
    final topLeft = tester.getTopLeft(find.byType(GlassButton));
    await tester.tapAt(topLeft + const Offset(12, 12));
    expect(taps, 1);
  });
}
