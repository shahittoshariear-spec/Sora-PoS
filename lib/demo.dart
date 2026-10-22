import 'dart:math';

import 'format.dart';
import 'models.dart';

/// A lived-in little shop, used for the demo and for checking the screens
/// without touching real data. Everything here is deterministic.
AppData buildDemoData() {
  final now = DateTime.now();
  final rng = Random(27);
  final categories = <Category>[
    Category(id: 'cat-coffee', name: 'Coffee & Tea'),
    Category(id: 'cat-bakery', name: 'Bakery'),
    Category(id: 'cat-pantry', name: 'Pantry'),
    Category(id: 'cat-home', name: 'Home'),
    Category(id: 'cat-pets', name: 'Pets'),
    Category(id: 'cat-fresh', name: 'Fresh'),
  ];

  Product p(String id, String name, String sku, String category, double price, double cost, double stock,
          [String search = '']) =>
      Product(
        id: id,
        name: name,
        sku: sku,
        searchName: search,
        categoryId: category,
        price: price,
        cost: cost,
        stock: stock,
        createdAt: now.subtract(const Duration(days: 90)),
      );

  final products = <Product>[
    p('p-flatwhite', 'Flat White', '600100100001', 'cat-coffee', 28, 9, 42, 'fw'),
    p('p-cappuccino', 'Cappuccino', '600100100002', 'cat-coffee', 30, 10, 38),
    p('p-coldbrew', 'Cold Brew', '600100100003', 'cat-coffee', 34, 12, 24),
    p('p-rooibos', 'Rooibos Latte', '600100100004', 'cat-coffee', 32, 10, 31),
    p('p-matcha', 'Matcha Latte', '600100100005', 'cat-coffee', 36, 14, 18),
    p('p-croissant', 'Butter Croissant', '600100200001', 'cat-bakery', 26, 9, 4),
    p('p-almond', 'Almond Croissant', '600100200002', 'cat-bakery', 32, 12, 12),
    p('p-sourdough', 'Sourdough Loaf', '600100200003', 'cat-bakery', 58, 22, 9),
    p('p-brownie', 'Chocolate Brownie', '600100200004', 'cat-bakery', 24, 8, 21),
    p('p-muffin', 'Blueberry Muffin', '600100200005', 'cat-bakery', 22, 7, 15),
    p('p-oliveoil', 'Extra Virgin Olive Oil', '600100300001', 'cat-pantry', 185, 120, 14),
    p('p-honey', 'Wildflower Honey', '600100300002', 'cat-pantry', 96, 58, 19),
    p('p-granola', 'House Granola', '600100300003', 'cat-pantry', 78, 34, 22),
    p('p-mug', 'Handmade Ceramic Mug', '600100400001', 'cat-home', 165, 70, 11),
    p('p-towel', 'Linen Tea Towel', '600100400002', 'cat-home', 120, 55, 7),
    p('p-candle', 'Soy Candle — Fynbos', '600100400003', 'cat-home', 210, 95, 3),
    p('p-dogfood', 'Dog Food 2kg', '600100500001', 'cat-pets', 149, 98, 6),
    p('p-cattreats', 'Cat Treats', '600100500002', 'cat-pets', 45, 26, 17),
    p('p-milk', 'Fresh Milk 1L', '600100600001', 'cat-fresh', 24, 18, 2),
    p('p-eggs', 'Free Range Eggs (6)', '600100600002', 'cat-fresh', 42, 30, 13),
    p('p-avocado', 'Avocado', '600100600003', 'cat-fresh', 18, 11, 26),
    p('p-tomatoes', 'Tomatoes 1kg', '600100600004', 'cat-fresh', 32, 20, 8),
  ];
  final byId = {for (final p in products) p.id: p};

  Staff person(String id, String name, Role role, String password) {
    final salt = Passwords.newSalt();
    return Staff(
      id: id,
      name: name,
      role: role,
      salt: salt,
      passwordHash: Passwords.hash(password, salt),
      createdAt: now.subtract(const Duration(days: 120)),
    );
  }

  final owner = person('s-owner', 'Ren Arn', Role.owner, 'demo1234');
  final manager = person('s-manager', 'Liam Harrison', Role.manager, 'manager1234');
  final cashier = person('s-cashier', 'Arif Rahman', Role.cashier, 'cashier1234');
  final staff = [owner, manager, cashier];

  final data = AppData(
    shop: ShopInfo(
      name: 'Sora & Co.',
      address: '18 Kloof Street\nCape Town 8001',
      phone: '+27 21 555 0148',
      currency: 'R',
      taxRate: 15,
      lowStock: 8,
      receiptFooter: 'Thank you for supporting our little shop.',
    ),
    settings: ShopSettings(
      chime: true,
      autoBackups: true,
      backupFrequency: 'weekly',
      demo: true,
    ),
    appearance: Appearance(themeId: 'teal', fontIndex: 0),
    categories: categories,
    products: products,
    staff: staff,
  );

  int number = 1001;
  final todayStart = startOfDay(now);

  for (int d = 44; d >= 0; d--) {
    final day = todayStart.subtract(Duration(days: d));
    final count = d == 0 ? (now.hour < 11 ? 2 : 5) : 3 + rng.nextInt(6);
    for (int i = 0; i < count; i++) {
      final hour = 8 + rng.nextInt(10);
      final minute = rng.nextInt(60);
      final at = DateTime(day.year, day.month, day.day, hour, minute);
      if (at.isAfter(now)) continue;
      final lineCount = 1 + rng.nextInt(4);
      final chosen = <String>{};
      while (chosen.length < lineCount) {
        chosen.add(products[rng.nextInt(products.length)].id);
      }
      final lines = chosen.map((id) {
        final prod = byId[id]!;
        final qty = (rng.nextInt(10) == 0 ? 2 : 1).toDouble();
        return SaleLine(
          productId: prod.id,
          name: prod.name,
          sku: prod.sku,
          unitPrice: prod.price,
          cost: prod.cost,
          qty: qty,
        );
      }).toList();
      final subtotal = round2(lines.fold(0.0, (a, l) => a + l.total));
      final tax = round2(subtotal * 0.15);
      final total = round2(subtotal + tax);
      final cashierForSale = rng.nextBool() ? cashier : owner;
      final mode = rng.nextInt(10);
      double cash = 0;
      double card = 0;
      double tendered = 0;
      double change = 0;
      if (mode < 6) {
        cash = total;
        tendered = (total / 10).ceilToDouble() * 10;
        change = round2(tendered - total);
      } else if (mode < 9) {
        card = total;
      } else {
        cash = (total * 0.4 / 10).roundToDouble() * 10;
        cash = min(cash, total);
        card = round2(total - cash);
      }
      data.sales.add(Sale(
        number: number++,
        at: at,
        lines: lines,
        subtotal: subtotal,
        tax: tax,
        total: total,
        cash: cash,
        card: card,
        cashTendered: tendered,
        change: change,
        cashierId: cashierForSale.id,
        cashierName: cashierForSale.name,
      ));
    }
  }

  // A few returns, a void, and one sale with a price set just for that sale.
  final candidates = data.sales.where((s) => now.difference(s.at).inDays < 12).toList();
  for (int i = 0; i < 5 && candidates.length > i * 3; i++) {
    final sale = candidates[i * 3];
    if (sale.lines.isEmpty) continue;
    final line = sale.lines.first;
    final qty = line.qty > 1 ? 1.0 : 1.0;
    final subtotal = round2(line.unitPrice * qty);
    final ratio = sale.subtotal == 0 ? 0.15 : sale.tax / sale.subtotal;
    final tax = round2(subtotal * ratio);
    final total = round2(subtotal + tax);
    data.refunds.add(RefundRecord(
      number: number++,
      saleNumber: sale.number,
      at: sale.at.add(const Duration(hours: 2)),
      lines: [line.copyWith(qty: qty)],
      subtotal: subtotal,
      tax: tax,
      total: total,
      cash: total,
      card: 0,
      method: 'Cash',
      cashierId: cashier.id,
      cashierName: cashier.name,
      authorisedBy: manager.name,
      reason: 'Customer changed their mind',
    ));
  }

  if (data.sales.length > 30) {
    final voided = data.sales[data.sales.length - 8];
    voided.voided = true;
    voided.voidedById = manager.id;
    voided.voidedByName = manager.name;
    voided.voidedAt = voided.at.add(const Duration(minutes: 25));
  }

  if (data.sales.length > 5) {
    final priced = data.sales[data.sales.length - 3];
    if (priced.lines.isNotEmpty) {
      final line = priced.lines.first;
      final old = line.unitPrice;
      final charged = round2(max(1, old - 6));
      line.unitPrice = charged;
      priced.subtotal = round2(priced.lines.fold(0.0, (a, l) => a + l.total));
      priced.tax = round2(priced.subtotal * 0.15);
      priced.total = round2(priced.subtotal + priced.tax);
      priced.cash = priced.card > 0 ? priced.cash : priced.total;
      data.audit.add(AuditEntry(
        at: priced.at,
        kind: 'price_override',
        title: 'A price set for one sale',
        detail:
            '${line.name}: shelf ${data.shop.currency}${old.toStringAsFixed(2)}, charged ${data.shop.currency}${charged.toStringAsFixed(2)}',
        productId: line.productId,
        by: cashier.name,
        before: old,
        after: charged,
      ));
    }
  }

  // A cart line that never made it into a completed sale.
  if (data.sales.isNotEmpty) {
    final sample = data.sales[data.sales.length - 2];
    if (sample.lines.isNotEmpty) {
      final line = sample.lines.first;
      final added = sample.at.subtract(const Duration(minutes: 2, seconds: 17));
      data.audit.add(AuditEntry(
        at: sample.at,
        kind: 'cart_removed',
        title: 'An item left the till before payment',
        detail:
            '${line.name} · 1 × ${data.shop.currency}${line.unitPrice.toStringAsFixed(2)} · added ${timeExact(added)} · removed ${timeExact(sample.at)} · waited 2m 17s · cart ${data.shop.currency}${sample.total.toStringAsFixed(2)} · sale #${sample.number} · removed from the sale',
        productId: line.productId,
        by: cashier.name,
        before: 1,
        after: 0,
      ));
    }
  }

  final todaySales = data.sales.where((s) => !s.voided && !s.at.isBefore(todayStart)).toList();
  final todayRefunds = data.refunds.where((r) => !r.at.isBefore(todayStart)).toList();
  data.audit.addAll([
    AuditEntry(
      at: todayStart.add(const Duration(hours: 9, minutes: 12)),
      kind: 'stock_edit',
      title: 'Stock typed over by hand',
      detail: 'Flat White · 40 → 36',
      productId: 'p-flatwhite',
      by: manager.name,
      before: 40,
      after: 36,
    ),
    AuditEntry(
      at: todayStart.add(const Duration(hours: 10, minutes: 41)),
      kind: 'held_discard',
      title: 'A held sale was thrown away',
      detail: 'Held sale · 3 items · R284.20',
      by: cashier.name,
    ),
    AuditEntry(
      at: todayStart.subtract(const Duration(days: 2, hours: -11)),
      kind: 'product_add',
      title: 'Product added',
      detail: 'Soy Candle — Fynbos · 3 on the shelf',
      productId: 'p-candle',
      by: owner.name,
      after: 3,
    ),
    AuditEntry(
      at: todayStart.subtract(const Duration(days: 7, hours: -15)),
      kind: 'import',
      title: 'Spreadsheet imported',
      detail: '4 added, 2 updated from products.xlsx',
      by: owner.name,
    ),
  ]);

  // A snapshot from yesterday lets the day report show stock no sale explains.
  final soldToday = <String, double>{};
  for (final sale in todaySales) {
    for (final l in sale.lines) {
      soldToday[l.productId] = (soldToday[l.productId] ?? 0) + l.qty;
    }
  }
  for (final refund in todayRefunds) {
    for (final l in refund.lines) {
      soldToday[l.productId] = (soldToday[l.productId] ?? 0) - l.qty;
    }
  }
  final snapshot = <String, double>{};
  for (final prod in products) {
    snapshot[prod.id] = round2(prod.stock + (soldToday[prod.id] ?? 0));
  }
  snapshot['p-dogfood'] = round2(snapshot['p-dogfood']! + 3);
  data.snapshots.add(StockSnapshot(
    date: dateKey(todayStart.subtract(const Duration(days: 1))),
    at: todayStart.subtract(const Duration(hours: 7)),
    stock: snapshot,
  ));

  data.holds.addAll([
    HeldSale(
      id: newId(),
      label: 'Table by the window',
      at: now.subtract(const Duration(minutes: 14)),
      lines: [
        SaleLine(
          productId: 'p-cappuccino',
          name: 'Cappuccino',
          sku: '600100100002',
          unitPrice: 30,
          cost: 10,
          qty: 2,
        ),
        SaleLine(
          productId: 'p-croissant',
          name: 'Butter Croissant',
          sku: '600100200001',
          unitPrice: 26,
          cost: 9,
          qty: 1,
        ),
      ],
      cashierId: cashier.id,
      cashierName: cashier.name,
    ),
    HeldSale(
      id: newId(),
      label: 'Regular — paying by card',
      at: now.subtract(const Duration(minutes: 38)),
      lines: [
        SaleLine(
          productId: 'p-sourdough',
          name: 'Sourdough Loaf',
          sku: '600100200003',
          unitPrice: 58,
          cost: 22,
          qty: 2,
        ),
        SaleLine(
          productId: 'p-honey',
          name: 'Wildflower Honey',
          sku: '600100300002',
          unitPrice: 96,
          cost: 58,
          qty: 1,
        ),
      ],
      cashierId: owner.id,
      cashierName: owner.name,
    ),
  ]);

  data.nextNumber = number;
  return data;
}
