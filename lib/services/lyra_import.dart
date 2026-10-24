import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../format.dart';
import '../models.dart';
import 'paths.dart';

/// Reads the data file Lyra PoS keeps in `%APPDATA%\Lyra PoS` and maps it to
/// Sora's document shape.
///
/// Lyra stores staff passwords as unsalted SHA-256. Sora uses a salted hash, so
/// the importer keeps every person and role but leaves their password empty.
/// The first-run flow sets the owner's new password before signing in; the
/// owner sets everyone else's in Setup → Staff.
class LyraImportException implements Exception {
  final String message;
  LyraImportException(this.message);
  @override
  String toString() => message;
}

class LyraImportPreview {
  final String path;
  final Map<String, dynamic> raw;
  final int staffCount;
  final int categoryCount;
  final int productCount;
  final int saleCount;
  final int refundCount;
  final int holdCount;
  final int auditCount;
  final String? ownerName;

  const LyraImportPreview({
    required this.path,
    required this.raw,
    required this.staffCount,
    required this.categoryCount,
    required this.productCount,
    required this.saleCount,
    required this.refundCount,
    required this.holdCount,
    required this.auditCount,
    required this.ownerName,
  });

  factory LyraImportPreview.fromRaw(String path, Map<String, dynamic> raw) {
    final staff = _list(raw['staff']);
    String? owner;
    for (final entry in staff) {
      final person = _map(entry);
      if (_str(person['role']).toLowerCase() == 'owner') {
        owner = _personName(person);
        break;
      }
    }
    final sales = _list(raw['sales']);
    var refunds = 0;
    for (final entry in sales) {
      if (_str(_map(entry)['type']) == 'return') refunds++;
    }
    return LyraImportPreview(
      path: path,
      raw: raw,
      staffCount: staff.length,
      categoryCount: _list(raw['categories']).length,
      productCount: _list(raw['products']).length,
      saleCount: sales.length - refunds,
      refundCount: refunds,
      holdCount: _list(raw['heldSales']).length,
      auditCount:
          _list(raw['stockLog']).length + _list(raw['changeLog']).length,
      ownerName: owner,
    );
  }

  String get summary {
    final parts = <String>[
      '$productCount products',
      '$categoryCount categories',
      '$saleCount sales',
      '$staffCount staff',
    ];
    if (refundCount > 0) parts.add('$refundCount refunds');
    if (holdCount > 0) parts.add('$holdCount holds');
    return parts.join(' · ');
  }
}

class LyraImportResult {
  final AppData data;
  final String ownerId;
  final String ownerName;
  final int products;
  final int categories;
  final int sales;
  final int refunds;
  final int holds;
  final int audit;
  final List<String> warnings;

  const LyraImportResult({
    required this.data,
    required this.ownerId,
    required this.ownerName,
    required this.products,
    required this.categories,
    required this.sales,
    required this.refunds,
    required this.holds,
    required this.audit,
    required this.warnings,
  });
}

/// The path Lyra PoS uses for its live data on this machine. A
/// `SORA_LYRA_DATA` override makes the importer testable on a fixture.
File lyraDataFile() {
  final override = Platform.environment['SORA_LYRA_DATA'];
  if (override != null && override.trim().isNotEmpty) {
    return File(override.trim());
  }
  final appData = Platform.environment['APPDATA'];
  final base =
      appData ?? Platform.environment['HOME'] ?? Directory.current.path;
  return File(joinPath(joinPath(base, 'Lyra PoS'), 'lyra-pos-data.json'));
}

Future<LyraImportPreview?> findLyraData() async {
  final file = lyraDataFile();
  if (!await file.exists()) return null;
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw LyraImportException(
        'The Lyra PoS data file is not a shop document.',
      );
    }
    return LyraImportPreview.fromRaw(
      file.path,
      Map<String, dynamic>.from(decoded),
    );
  } on LyraImportException {
    rethrow;
  } catch (e) {
    throw LyraImportException('Could not read the Lyra PoS data file: $e');
  }
}

/// Builds a complete Sora document from a preview. This is pure: it does not
/// touch either app's files.
LyraImportResult buildLyraImportData(
  LyraImportPreview preview, {
  required String ownerPassword,
}) {
  if (ownerPassword.length < 4) {
    throw LyraImportException('Use at least four characters for the password.');
  }
  final raw = preview.raw;
  final settings = _map(raw['settings']);
  final lyraStaff = _list(raw['staff']);
  if (lyraStaff.isEmpty) {
    throw LyraImportException('The Lyra PoS data file has no staff accounts.');
  }
  var ownerIndex = -1;
  for (var i = 0; i < lyraStaff.length; i++) {
    if (_str(_map(lyraStaff[i])['role']).toLowerCase() == 'owner') {
      ownerIndex = i;
      break;
    }
  }
  if (ownerIndex == -1) {
    throw LyraImportException('The Lyra PoS data file has no owner account.');
  }

  final warnings = <String>[];
  final now = DateTime.now();
  final staff = <Staff>[];
  String ownerId = '';
  String ownerName = '';
  for (var i = 0; i < lyraStaff.length; i++) {
    final person = _map(lyraStaff[i]);
    final name = _personName(person);
    if (name.isEmpty) continue;
    final id = _str(person['id']).isEmpty ? newId() : _str(person['id']);
    final role = roleFrom(_str(person['role']));
    final isOwner = i == ownerIndex;
    final salt = isOwner ? Passwords.newSalt() : '';
    final hash = isOwner ? Passwords.hash(ownerPassword, salt) : '';
    if (isOwner) {
      ownerId = id;
      ownerName = name;
    }
    staff.add(
      Staff(
        id: id,
        name: name,
        role: role,
        passwordHash: hash,
        salt: salt,
        createdAt: now,
      ),
    );
  }
  if (ownerId.isEmpty) {
    throw LyraImportException('The Lyra PoS owner account has no name.');
  }

  final categoryByName = <String, Category>{};
  final categories = <Category>[];
  Category categoryFor(String name) {
    final clean = name.trim();
    final key = clean.toLowerCase();
    final existing = categoryByName[key];
    if (existing != null) return existing;
    final category = Category(
      id: newId(),
      name: clean.isEmpty ? 'General' : clean,
    );
    categoryByName[key] = category;
    categories.add(category);
    return category;
  }

  for (final entry in _list(raw['categories'])) {
    final name = _str(entry).trim();
    if (name.isNotEmpty) categoryFor(name);
  }
  if (categories.isEmpty) categoryFor('General');

  final products = <Product>[];
  final productById = <String, Product>{};
  var supplierWarned = false;
  for (final entry in _list(raw['products'])) {
    final item = _map(entry);
    final name = _str(item['name']).trim();
    if (name.isEmpty) continue;
    final id = _str(item['id']).isEmpty ? newId() : _str(item['id']);
    final category = categoryFor(_str(item['category']));
    final sku = _str(item['sku']);
    final alias = _str(item['alias']);
    final supplier = _str(item['supplier']);
    final search = <String>[
      name,
      sku,
      alias,
      supplier,
    ].where((part) => part.trim().isNotEmpty).join(' ');
    final product = Product(
      id: id,
      name: name,
      sku: sku,
      searchName: search,
      categoryId: category.id,
      price: _double(item['price']),
      cost: _double(item['cost']),
      stock: _double(item['stock']),
      createdAt: now,
      updatedAt: now,
    );
    products.add(product);
    productById[id] = product;
    if (supplier.isNotEmpty) {
      if (!supplierWarned) {
        warnings.add('Supplier names are not carried into Sora.');
        supplierWarned = true;
      }
    }
  }

  final rawSales = _list(raw['sales']);
  final numberById = <String, int>{};
  var maxNumber = 1000;
  for (final entry in rawSales) {
    final sale = _map(entry);
    final number = _int(sale['number']);
    final id = _str(sale['id']);
    if (id.isNotEmpty) numberById[id] = number;
    maxNumber = math.max(maxNumber, number);
  }

  final sales = <Sale>[];
  final refunds = <RefundRecord>[];
  var missingCashier = false;
  for (final entry in rawSales) {
    final item = _map(entry);
    final at = _date(item['date']);
    final lines = _lines(_list(item['items']), productById, at);
    final subtotal = _double(item['subtotal']);
    final tax = _double(item['tax']);
    final total = _double(item['total']);
    final method = _str(item['paymentMethod']);
    final payment = _payment(item, method, total);
    final cashierId = _str(item['cashierId']);
    final cashierName = _str(item['cashier']);
    if (cashierId.isEmpty && cashierName.isEmpty) missingCashier = true;
    final shownCashier = cashierName.isEmpty ? 'Imported (Lyra)' : cashierName;
    final authorisedBy = _str(item['authorisedBy']);
    final number = _int(item['number']);

    if (_str(item['type']) == 'return') {
      var soldNumber = _int(item['refundOfNumber']);
      if (soldNumber == 0) {
        soldNumber = numberById[_str(item['refundOf'])] ?? 0;
      }
      refunds.add(
        RefundRecord(
          number: number,
          saleNumber: soldNumber,
          at: at,
          lines: lines,
          subtotal: subtotal.abs(),
          tax: tax.abs(),
          total: total.abs(),
          cash: payment.$1.abs(),
          card: payment.$2.abs(),
          method: method.isEmpty ? 'Cash' : method,
          cashierId: cashierId,
          cashierName: shownCashier,
          authorisedBy: authorisedBy,
        ),
      );
    } else {
      final voidedAt = _str(item['voidedAt']);
      sales.add(
        Sale(
          number: number,
          at: at,
          lines: lines,
          subtotal: subtotal,
          tax: tax,
          total: total,
          cash: payment.$1,
          card: payment.$2,
          cashTendered: _double(item['tendered']),
          change: _double(item['change']),
          cashierId: cashierId,
          cashierName: shownCashier,
          voided: voidedAt.isNotEmpty,
          voidedById: _str(item['voidedById']).isEmpty
              ? null
              : _str(item['voidedById']),
          voidedByName: _str(item['voidedBy']).isEmpty
              ? null
              : _str(item['voidedBy']),
          voidedAt: voidedAt.isEmpty ? null : _date(voidedAt),
          note: authorisedBy.isEmpty
              ? null
              : 'Authorised by $authorisedBy (Lyra import)',
        ),
      );
    }
  }
  if (missingCashier) {
    warnings.add(
      'Some older sales had no cashier name; they are labelled Imported (Lyra).',
    );
  }

  final holds = <HeldSale>[];
  for (final entry in _list(raw['heldSales'])) {
    final item = _map(entry);
    final at = _date(item['createdAt']);
    holds.add(
      HeldSale(
        id: _str(item['id']).isEmpty ? newId() : _str(item['id']),
        label: 'Imported from Lyra PoS',
        at: at,
        lines: _lines(_list(item['cart']), productById, at),
        cashierId: '',
        cashierName: 'Imported (Lyra)',
      ),
    );
  }

  final audit = <AuditEntry>[];
  for (final entry in _list(raw['stockLog'])) {
    final item = _map(entry);
    final name = _str(item['name']);
    audit.add(
      AuditEntry(
        at: _date(item['at']),
        kind: 'stock_edit',
        title: 'Stock changed by hand',
        detail:
            '$name · ${_int(item['from'])} → ${_int(item['to'])} · Lyra import',
        productId: _str(item['productId']).isEmpty
            ? null
            : _str(item['productId']),
        by: _str(item['by']).isEmpty ? null : _str(item['by']),
        before: _double(item['from']),
        after: _double(item['to']),
      ),
    );
  }
  for (final entry in _list(raw['changeLog'])) {
    final item = _map(entry);
    final kind = _auditKind(_str(item['kind']));
    audit.add(
      AuditEntry(
        at: _date(item['at']),
        kind: kind,
        title: _auditTitle(kind),
        detail: _str(item['detail']).isEmpty
            ? '${_str(item['name'])} · Lyra import'
            : '${_str(item['name'])} · ${_str(item['detail'])} · Lyra import',
        by: _str(item['by']).isEmpty ? null : _str(item['by']),
      ),
    );
  }
  audit.add(
    AuditEntry(
      at: now,
      kind: 'import',
      title: 'Shop imported from Lyra PoS',
      detail:
          '${products.length} products · ${categories.length} categories · ${sales.length} sales · ${staff.length} staff',
      by: ownerName,
    ),
  );

  final snapshots = <StockSnapshot>[];
  final snapshot = _map(raw['stockSnapshot']);
  final snapshotItems = _list(snapshot['items']);
  if (snapshotItems.isNotEmpty) {
    final at = _date(snapshot['at']);
    final stock = <String, double>{};
    for (final entry in snapshotItems) {
      final item = _map(entry);
      final id = _str(item['id']);
      if (id.isNotEmpty) stock[id] = _double(item['stock']);
    }
    if (stock.isNotEmpty) {
      snapshots.add(StockSnapshot(date: dateKey(at), at: at, stock: stock));
    }
  }

  final customThemes = _customThemes(settings['customThemes']);
  final appearance = Appearance(
    themeId: _themeId(_str(settings['theme'])),
    fontIndex: _fontIndex(_str(settings['fontFamily'])),
    textScale: _textScale(_str(settings['fontSize'])),
    navPosition: _str(settings['navLayout']) == 'top' ? 'top' : 'side',
    dockNav: false,
    surfaceStyle: 'glass',
    customs: customThemes,
  );

  final shortcuts = defaultShortcuts();
  final importedShortcuts = _map(settings['shortcuts']);
  for (final entry in importedShortcuts.entries) {
    final action = _shortcutAction(entry.key);
    if (action == null) continue;
    final binding = _map(entry.value);
    shortcuts[action] = ShortcutBinding(
      action: action,
      keys: _str(binding['key']),
      hold: _str(binding['mode']) == 'hold',
    );
  }

  final lowStock = _double(settings['lowStockThreshold']);
  final receiptWidth = _double(settings['receiptWidth']);
  final data = AppData(
    shop: ShopInfo(
      name: _str(settings['shopName']).isEmpty
          ? 'My Shop'
          : _str(settings['shopName']),
      address: _str(settings['address']),
      phone: _str(settings['phone']),
      currency: _str(settings['currency']).isEmpty
          ? 'R'
          : _str(settings['currency']),
      taxRate: _double(settings['taxRate']),
      lowStock: lowStock == 0 ? 5 : lowStock,
      receiptFooter: _str(settings['receiptFooter']).isEmpty
          ? 'Thank you for shopping with us.'
          : _str(settings['receiptFooter']),
    ),
    settings: ShopSettings(
      chime: _bool(settings['saleSound'], true),
      cutPaper: _bool(settings['receiptCutPaper'], false),
      autoEmail: _bool(settings['reportAuto'], false),
      autoBackups: _bool(settings['backupAuto'], true),
      backupFrequency: _backupFrequency(_str(settings['backupEvery'])),
      receiptPrinter: _str(settings['receiptPrinter']),
      emailAddress: _str(settings['reportEmail']),
      emailTime: _str(settings['reportAutoTime']).isEmpty
          ? '17:30'
          : _str(settings['reportAutoTime']),
      pendingReports: [],
      demo: false,
      tillPanelFraction: receiptWidth <= 0
          ? 0.34
          : receiptWidth.clamp(0.28, 1.0).toDouble(),
      tillRightView: 'cart',
    ),
    appearance: appearance,
    products: products,
    categories: categories,
    staff: staff,
    sales: sales,
    refunds: refunds,
    holds: holds,
    audit: audit,
    snapshots: snapshots,
    shortcuts: shortcuts,
    nextNumber: math.max(1001, _int(raw['nextSaleNumber'])),
  );

  return LyraImportResult(
    data: data,
    ownerId: ownerId,
    ownerName: ownerName,
    products: products.length,
    categories: categories.length,
    sales: sales.length,
    refunds: refunds.length,
    holds: holds.length,
    audit: audit.length,
    warnings: warnings,
  );
}

List<SaleLine> _lines(
  List<dynamic> items,
  Map<String, Product> products,
  DateTime at,
) {
  final lines = <SaleLine>[];
  for (final entry in items) {
    final item = _map(entry);
    final productId = _str(item['productId']);
    final product = products[productId];
    final qty = _double(item['qty']);
    lines.add(
      SaleLine(
        productId: productId,
        name: _str(item['name']).isEmpty
            ? (product?.name ?? 'Imported item')
            : _str(item['name']),
        sku: product?.sku ?? '',
        unitPrice: _double(item['price']),
        cost: item.containsKey('cost')
            ? _double(item['cost'])
            : (product?.cost ?? 0),
        qty: qty == 0 ? 1 : qty,
        addedAt: at,
      ),
    );
  }
  return lines;
}

(double, double) _payment(
  Map<String, dynamic> item,
  String method,
  double total,
) {
  if (item['cashPaid'] != null || item['cardPaid'] != null) {
    return (_double(item['cashPaid']), _double(item['cardPaid']));
  }
  final lower = method.toLowerCase();
  final cash = lower.contains('cash');
  final card = lower.contains('card');
  if (cash && card) return (total, 0);
  if (card) return (0, total);
  return (total, 0);
}

String _personName(Map<String, dynamic> person) {
  final name = _str(person['name']).trim();
  final surname = _str(person['surname']).trim();
  return [name, surname].where((part) => part.isNotEmpty).join(' ');
}

String _themeId(String lyra) {
  return switch (lyra) {
    'midnight' => 'blue',
    'galaxy' => 'violet',
    'cosmos' => 'green',
    'moonlight' => 'graphite',
    'rust' => 'orange',
    'custom-1' => 'custom0',
    'custom-2' => 'custom1',
    'custom-3' => 'custom2',
    _ => 'teal',
  };
}

int _fontIndex(String lyra) {
  return switch (lyra) {
    'calibri' => 4,
    'candara' => 1,
    'trebuchet' => 5,
    'verdana' => 0,
    'georgia' => 7,
    'cambria' => 7,
    'mono' => 8,
    'consolas' => 8,
    _ => 0,
  };
}

double _textScale(String lyra) {
  return switch (lyra) {
    'compact' => 0.9,
    'large' => 1.1,
    'huge' => 1.22,
    _ => 1.0,
  };
}

String _backupFrequency(String lyra) {
  return switch (lyra) {
    'day' => 'daily',
    'month' => 'monthly',
    _ => 'weekly',
  };
}

String? _shortcutAction(String lyra) {
  return switch (lyra) {
    'viewTill' => 'go.till',
    'viewStock' => 'go.stock',
    'viewLedger' => 'go.ledger',
    'viewDashboard' => 'go.overview',
    'viewReports' => 'go.reports',
    'viewSettings' => 'go.setup',
    'tillFocus' => 'focus.search',
    'tillCharge' => 'pay',
    'tillHold' => 'hold',
    'tillEmail' => 'email.report',
    'tillHide' => 'toggle.products',
    'stockAdd' => 'add.product',
    'stockClearFilter' => 'clear.filter',
    'stockDelete' => 'delete.ticked',
    _ => null,
  };
}

String _auditKind(String lyra) {
  return switch (lyra) {
    'price' => 'price_change',
    'cost' => 'cost_change',
    'added' => 'product_add',
    'deleted' => 'product_delete',
    'discarded' => 'held_discard',
    'void' => 'void',
    _ => 'import',
  };
}

String _auditTitle(String kind) {
  return switch (kind) {
    'price_change' => 'Price changed',
    'cost_change' => 'Cost changed',
    'product_add' => 'Product added',
    'product_delete' => 'Product deleted',
    'held_discard' => 'Held sale discarded',
    'void' => 'Sale voided',
    _ => 'Change from Lyra PoS',
  };
}

List<CustomTheme> _customThemes(Object? value) {
  final list = _list(value);
  final defaults = Appearance().customs;
  final result = <CustomTheme>[];
  for (var i = 0; i < 3; i++) {
    final entry = i < list.length ? _map(list[i]) : const <String, dynamic>{};
    final accent = _hexColor(_str(entry['accent']));
    final night = _hexColor(_str(entry['background']));
    result.add(
      CustomTheme(
        name: 'Imported ${['I', 'II', 'III'][i]}',
        accent: accent ?? defaults[i].accent,
        night: night ?? defaults[i].night,
      ),
    );
  }
  return result;
}

int? _hexColor(String value) {
  var hex = value.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 3) {
    hex = '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}';
  }
  if (hex.length != 6) return null;
  final rgb = int.tryParse(hex, radix: 16);
  return rgb == null ? null : 0xFF000000 | rgb;
}

DateTime _date(Object? value) {
  final text = _str(value);
  final parsed = DateTime.tryParse(text);
  return parsed == null ? DateTime.now() : parsed.toLocal();
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<dynamic> _list(Object? value) => value is List ? value : const [];

String _str(Object? value) => value == null ? '' : value.toString();

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(_str(value)) ?? 0;
}

double _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(_str(value)) ?? 0;
}

bool _bool(Object? value, bool fallback) {
  if (value is bool) return value;
  return fallback;
}
