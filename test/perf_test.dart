import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sora_pos/cart.dart';
import 'package:sora_pos/demo.dart';
import 'package:sora_pos/models.dart';
import 'package:sora_pos/screens/till.dart';
import 'package:sora_pos/store.dart';
import 'package:sora_pos/ui/product_visual.dart';
import 'package:sora_pos/ui/theme.dart';

void main() {
  testWidgets('a large catalogue only builds the visible till tiles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(3000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = Store();
    final data = buildDemoData();
    final source = data.products.first;
    data.products = List<Product>.generate(2580, (i) {
      return Product(
        id: 'p$i',
        name: '${source.name} $i',
        sku: 'SKU$i',
        categoryId: source.categoryId,
        price: source.price,
        cost: source.cost,
        stock: source.stock,
      );
    });
    store.data = data;
    store.current = store.owner;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildSoraTheme(SoraPalette.named.first, 0),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(3000, 1800),
            textScaler: TextScaler.linear(0.55),
          ),
          child: Scaffold(
            body: TillScreen(store: store, cart: CartController()),
          ),
        ),
      ),
    );
    await tester.pump();

    final built = find.byType(ProductMark).evaluate().length;
    // ignore: avoid_print
    print('till tiles built=$built');
    expect(built, lessThan(400));
  });
}
