import 'package:flutter_test/flutter_test.dart';
import 'package:sora_pos/models.dart';
import 'package:sora_pos/services/lyra_import.dart';

void main() {
  Map<String, dynamic> lyraDocument() => {
    'settings': {
      'shopName': 'Sora & Co.',
      'address': '12 Main Road',
      'phone': '012 345 6789',
      'currency': 'R',
      'taxRate': 15,
      'lowStockThreshold': 5,
      'receiptFooter': 'Thank you',
      'receiptPrinter': 'EPSON TM-T20',
      'receiptCutPaper': true,
      'reportAuto': true,
      'reportEmail': 'owner@example.com',
      'reportAutoTime': '17:30',
      'backupAuto': true,
      'backupEvery': 'week',
      'theme': 'midnight',
      'fontFamily': 'segoe',
      'fontSize': 'large',
      'navLayout': 'top',
      'receiptWidth': 0.5,
      'saleSound': true,
      'shortcuts': {
        'viewTill': {'key': 'Ctrl+1', 'mode': 'press'},
        'stockClearFilter': {'key': '', 'mode': 'hold'},
      },
      'customThemes': [
        {'accent': '#112233', 'background': '#010203'},
      ],
    },
    'staff': [
      {
        'id': 'lyra-owner',
        'name': 'Ren',
        'surname': 'Arn',
        'role': 'owner',
        'passwordHash': 'old-hash',
      },
      {
        'id': 'lyra-cashier',
        'name': 'Arif',
        'surname': 'Rahman',
        'role': 'cashier',
        'passwordHash': 'old-hash',
      },
    ],
    'categories': ['General', 'Coffee'],
    'products': [
      {
        'id': 'p1',
        'name': 'Cappuccino',
        'sku': 'CAP-1',
        'category': 'Coffee',
        'price': 30.0,
        'cost': 12.0,
        'stock': 10,
      },
    ],
    'sales': [
      {
        'id': 's1',
        'number': 1001,
        'date': '2026-10-22T10:00:00.000Z',
        'type': 'sale',
        'items': [
          {
            'productId': 'p1',
            'name': 'Cappuccino',
            'price': 30.0,
            'qty': 2,
            'lineTotal': 60.0,
            'cost': 12.0,
          },
        ],
        'subtotal': 60.0,
        'tax': 0.0,
        'total': 60.0,
        'paymentMethod': 'Cash + Card',
        'tendered': 40.0,
        'change': 0.0,
        'cashPaid': 20.0,
        'cardPaid': 40.0,
      },
      {
        'id': 'r1',
        'number': 1002,
        'date': '2026-10-22T11:00:00.000Z',
        'type': 'return',
        'refundOf': 's1',
        'refundOfNumber': 1001,
        'items': [
          {
            'productId': 'p1',
            'name': 'Cappuccino',
            'price': 30.0,
            'qty': 1,
            'lineTotal': 30.0,
            'cost': 12.0,
          },
        ],
        'subtotal': -30.0,
        'tax': 0.0,
        'total': -30.0,
        'paymentMethod': 'Card',
        'cashierId': 'lyra-owner',
        'cashier': 'Ren Arn',
        'authorisedBy': 'Ren Arn',
        'cardPaid': -30.0,
      },
    ],
    'heldSales': [
      {
        'id': 'h1',
        'createdAt': '2026-10-22T12:00:00.000Z',
        'cart': [
          {'productId': 'p1', 'name': 'Cappuccino', 'price': 30.0, 'qty': 1},
        ],
      },
    ],
    'stockLog': [
      {
        'at': '2026-10-22T09:00:00.000Z',
        'productId': 'p1',
        'name': 'Cappuccino',
        'from': 10,
        'to': 8,
        'by': 'Ren Arn',
      },
    ],
    'changeLog': [
      {
        'at': '2026-10-22T09:30:00.000Z',
        'kind': 'price',
        'name': 'Cappuccino',
        'detail': 'R30.00 → R32.00',
        'by': 'Ren Arn',
      },
    ],
    'stockSnapshot': {
      'at': '2026-10-22T09:00:00.000Z',
      'items': [
        {'id': 'p1', 'name': 'Cappuccino', 'stock': 10},
      ],
    },
    'nextSaleNumber': 1003,
    'nextProductId': 2,
  };

  test('Lyra data maps into a Sora shop', () {
    final preview = LyraImportPreview.fromRaw('test', lyraDocument());
    expect(preview.ownerName, 'Ren Arn');
    expect(preview.staffCount, 2);
    expect(preview.productCount, 1);
    expect(preview.saleCount, 1);
    expect(preview.refundCount, 1);
    expect(preview.holdCount, 1);

    final result = buildLyraImportData(preview, ownerPassword: 'newpass');
    final data = result.data;

    expect(result.ownerName, 'Ren Arn');
    expect(data.shop.name, 'Sora & Co.');
    expect(data.shop.address, '12 Main Road');
    expect(data.shop.currency, 'R');
    expect(data.shop.taxRate, 15);
    expect(data.shop.lowStock, 5);
    expect(data.settings.receiptPrinter, 'EPSON TM-T20');
    expect(data.settings.cutPaper, true);
    expect(data.settings.autoEmail, true);
    expect(data.settings.emailAddress, 'owner@example.com');
    expect(data.settings.backupFrequency, 'weekly');
    expect(data.settings.tillPanelFraction, 0.5);
    expect(data.appearance.themeId, 'blue');
    expect(data.appearance.fontIndex, 0);
    expect(data.appearance.textScale, 1.1);
    expect(data.appearance.navPosition, 'top');
    expect(data.appearance.customs.first.accent, 0xFF112233);
    expect(data.appearance.customs.first.night, 0xFF010203);
    expect(data.shortcuts['go.till']?.keys, 'Ctrl+1');
    expect(data.shortcuts['clear.filter']?.hold, true);
    expect(data.nextNumber, 1003);

    expect(data.categories.any((c) => c.name == 'Coffee'), isTrue);
    final product = data.products.single;
    expect(product.id, 'p1');
    expect(product.name, 'Cappuccino');
    expect(product.sku, 'CAP-1');
    expect(product.price, 30);
    expect(product.cost, 12);
    expect(product.stock, 10);
    expect(data.categories.any((c) => c.id == product.categoryId), isTrue);

    final owner = data.staff.firstWhere((s) => s.role == Role.owner);
    final cashier = data.staff.firstWhere((s) => s.role == Role.cashier);
    expect(owner.needsPassword, isFalse);
    expect(owner.matches('newpass'), isTrue);
    expect(cashier.needsPassword, isTrue);
    expect(cashier.matches('old-hash'), isFalse);

    expect(data.sales, hasLength(1));
    expect(data.sales.single.number, 1001);
    expect(data.sales.single.cash, 20);
    expect(data.sales.single.card, 40);
    expect(data.sales.single.cashierName, 'Imported (Lyra)');

    expect(data.refunds, hasLength(1));
    expect(data.refunds.single.saleNumber, 1001);
    expect(data.refunds.single.total, 30);
    expect(data.refunds.single.card, 30);
    expect(data.refunds.single.authorisedBy, 'Ren Arn');

    expect(data.holds, hasLength(1));
    expect(data.holds.single.lines.single.name, 'Cappuccino');
    expect(data.audit.any((a) => a.kind == 'stock_edit'), isTrue);
    expect(data.audit.any((a) => a.kind == 'price_change'), isTrue);
    expect(data.audit.any((a) => a.kind == 'import'), isTrue);
    expect(data.snapshots, hasLength(1));
    expect(data.snapshots.single.stock['p1'], 10);
  });

  test('a Lyra file without an owner is refused', () {
    final raw = lyraDocument();
    raw['staff'] = [
      {
        'id': 'c1',
        'name': 'Only',
        'surname': 'Cashier',
        'role': 'cashier',
        'passwordHash': 'old-hash',
      },
    ];
    final preview = LyraImportPreview.fromRaw('test', raw);
    expect(
      () => buildLyraImportData(preview, ownerPassword: 'newpass'),
      throwsA(isA<LyraImportException>()),
    );
  });
}
