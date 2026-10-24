import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// ---------------------------------------------------------------- helpers

double round2(double v) => (v * 100).roundToDouble() / 100;

double asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0;
  return 0;
}

int asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

String asString(dynamic v) => v == null ? '' : v.toString();

DateTime asDate(dynamic v, [DateTime? fallback]) {
  if (v is DateTime) return v;
  if (v is String)
    return DateTime.tryParse(v)?.toLocal() ?? fallback ?? DateTime.now();
  return fallback ?? DateTime.now();
}

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime startOfWeek(DateTime d) {
  final day = startOfDay(d);
  return day.subtract(Duration(days: (day.weekday - DateTime.monday) % 7));
}

DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
DateTime startOfYear(DateTime d) => DateTime(d.year, 1, 1);

String newId() {
  final r = Random.secure().nextInt(0xFFFFFF);
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${r.toRadixString(36)}';
}

/// ---------------------------------------------------------------- security

class Passwords {
  static String newSalt() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String hash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt::sora::$password')).toString();
}

/// ---------------------------------------------------------------- roles

enum Role { cashier, manager, owner }

extension RoleName on Role {
  String get id => name;

  String get label => switch (this) {
    Role.cashier => 'Cashier',
    Role.manager => 'Manager',
    Role.owner => 'Owner',
  };

  bool get canManageStock => this == Role.manager || this == Role.owner;
  bool get canSeeRecords => this == Role.owner;
}

Role roleFrom(String value) => Role.values.firstWhere(
  (r) => r.id == value || r.label.toLowerCase() == value.toLowerCase(),
  orElse: () => Role.cashier,
);

/// ---------------------------------------------------------------- products

class Product {
  String id;
  String name;
  String sku;
  String searchName;
  String categoryId;
  double price;
  double cost;
  double stock;
  DateTime createdAt;
  DateTime updatedAt;

  Product({
    required this.id,
    required this.name,
    this.sku = '',
    this.searchName = '',
    this.categoryId = '',
    this.price = 0,
    this.cost = 0,
    this.stock = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  double get valueAtCost => round2(max(0, stock) * cost);
  double get valueAtSell => round2(max(0, stock) * price);

  Product copyWith({
    String? name,
    String? sku,
    String? searchName,
    String? categoryId,
    double? price,
    double? cost,
    double? stock,
  }) => Product(
    id: id,
    name: name ?? this.name,
    sku: sku ?? this.sku,
    searchName: searchName ?? this.searchName,
    categoryId: categoryId ?? this.categoryId,
    price: price ?? this.price,
    cost: cost ?? this.cost,
    stock: stock ?? this.stock,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sku': sku,
    'searchName': searchName,
    'categoryId': categoryId,
    'price': price,
    'cost': cost,
    'stock': stock,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Product.fromJson(Map<String, dynamic> j) => Product(
    id: asString(j['id']).isEmpty ? newId() : asString(j['id']),
    name: asString(j['name']),
    sku: asString(j['sku']),
    searchName: asString(j['searchName']),
    categoryId: asString(j['categoryId']),
    price: asDouble(j['price']),
    cost: asDouble(j['cost']),
    stock: asDouble(j['stock']),
    createdAt: asDate(j['createdAt']),
    updatedAt: asDate(j['updatedAt']),
  );
}

class Category {
  String id;
  String name;

  Category({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory Category.fromJson(Map<String, dynamic> j) => Category(
    id: asString(j['id']).isEmpty ? newId() : asString(j['id']),
    name: asString(j['name']),
  );
}

/// ------------------------------------------------------------------ staff

class Staff {
  String id;
  String name;
  Role role;
  String passwordHash;
  String salt;
  DateTime createdAt;

  Staff({
    required this.id,
    required this.name,
    required this.role,
    required this.passwordHash,
    required this.salt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters2;
    return '${parts.first.characters2}${parts.last.characters2}';
  }

  bool get needsPassword => passwordHash.isEmpty || salt.isEmpty;

  bool matches(String password) =>
      !needsPassword && Passwords.hash(password, salt) == passwordHash;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'role': role.id,
    'passwordHash': passwordHash,
    'salt': salt,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Staff.fromJson(Map<String, dynamic> j) => Staff(
    id: asString(j['id']).isEmpty ? newId() : asString(j['id']),
    name: asString(j['name']),
    role: roleFrom(asString(j['role'])),
    passwordHash: asString(j['passwordHash']),
    salt: asString(j['salt']),
    createdAt: asDate(j['createdAt']),
  );
}

extension on String {
  String get characters2 => isEmpty ? '?' : substring(0, 1).toUpperCase();
}

/// -------------------------------------------------------------- sale lines

class SaleLine {
  String productId;
  String name;
  String sku;
  double unitPrice;
  double cost;
  double qty;
  DateTime addedAt;

  SaleLine({
    required this.productId,
    required this.name,
    this.sku = '',
    required this.unitPrice,
    this.cost = 0,
    this.qty = 1,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  double get total => round2(unitPrice * qty);
  double get profit => round2((unitPrice - cost) * qty);

  SaleLine copyWith({double? qty, double? unitPrice}) => SaleLine(
    productId: productId,
    name: name,
    sku: sku,
    unitPrice: unitPrice ?? this.unitPrice,
    cost: cost,
    qty: qty ?? this.qty,
    addedAt: addedAt,
  );

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'name': name,
    'sku': sku,
    'unitPrice': unitPrice,
    'cost': cost,
    'qty': qty,
    'addedAt': addedAt.toIso8601String(),
  };

  factory SaleLine.fromJson(Map<String, dynamic> j) => SaleLine(
    productId: asString(j['productId']),
    name: asString(j['name']),
    sku: asString(j['sku']),
    unitPrice: asDouble(j['unitPrice']),
    cost: asDouble(j['cost']),
    qty: asDouble(j['qty']) == 0 ? 1 : asDouble(j['qty']),
    addedAt: j['addedAt'] == null ? null : asDate(j['addedAt']),
  );
}

/// ------------------------------------------------------------------- sales

class Sale {
  int number;
  DateTime at;
  List<SaleLine> lines;
  double subtotal;
  double tax;
  double total;
  double cash;
  double card;
  double cashTendered;
  double change;
  String cashierId;
  String cashierName;
  bool voided;
  String? voidedById;
  String? voidedByName;
  DateTime? voidedAt;
  String? note;

  Sale({
    required this.number,
    required this.at,
    required this.lines,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.cash,
    required this.card,
    this.cashTendered = 0,
    this.change = 0,
    required this.cashierId,
    required this.cashierName,
    this.voided = false,
    this.voidedById,
    this.voidedByName,
    this.voidedAt,
    this.note,
  });

  double get itemCount => lines.fold(0, (a, l) => a + l.qty);
  double get cogs => round2(lines.fold(0, (a, l) => a + l.cost * l.qty));
  double get grossProfit => round2(subtotal - cogs);
  String get paymentLabel {
    if (voided) return 'Void';
    if (cash > 0 && card > 0) return 'Split';
    if (card > 0) return 'Card';
    return 'Cash';
  }

  Map<String, dynamic> toJson() => {
    'number': number,
    'at': at.toIso8601String(),
    'lines': lines.map((l) => l.toJson()).toList(),
    'subtotal': subtotal,
    'tax': tax,
    'total': total,
    'cash': cash,
    'card': card,
    'cashTendered': cashTendered,
    'change': change,
    'cashierId': cashierId,
    'cashierName': cashierName,
    'voided': voided,
    'voidedById': voidedById,
    'voidedByName': voidedByName,
    'voidedAt': voidedAt?.toIso8601String(),
    'note': note,
  };

  factory Sale.fromJson(Map<String, dynamic> j) => Sale(
    number: asInt(j['number']),
    at: asDate(j['at']),
    lines: (j['lines'] as List? ?? [])
        .map((e) => SaleLine.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    subtotal: asDouble(j['subtotal']),
    tax: asDouble(j['tax']),
    total: asDouble(j['total']),
    cash: asDouble(j['cash']),
    card: asDouble(j['card']),
    cashTendered: asDouble(j['cashTendered']),
    change: asDouble(j['change']),
    cashierId: asString(j['cashierId']),
    cashierName: asString(j['cashierName']),
    voided: j['voided'] == true,
    voidedById: j['voidedById'] as String?,
    voidedByName: j['voidedByName'] as String?,
    voidedAt: j['voidedAt'] == null ? null : asDate(j['voidedAt']),
    note: j['note'] as String?,
  );
}

class RefundRecord {
  int number;
  int saleNumber;
  DateTime at;
  List<SaleLine> lines;
  double subtotal;
  double tax;
  double total;
  double cash;
  double card;
  String method;
  String cashierId;
  String cashierName;
  String authorisedBy;
  String? reason;

  RefundRecord({
    required this.number,
    required this.saleNumber,
    required this.at,
    required this.lines,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.cash,
    required this.card,
    required this.method,
    required this.cashierId,
    required this.cashierName,
    this.authorisedBy = '',
    this.reason,
  });

  double get itemCount => lines.fold(0, (a, l) => a + l.qty);
  double get cogs => round2(lines.fold(0, (a, l) => a + l.cost * l.qty));

  Map<String, dynamic> toJson() => {
    'number': number,
    'saleNumber': saleNumber,
    'at': at.toIso8601String(),
    'lines': lines.map((l) => l.toJson()).toList(),
    'subtotal': subtotal,
    'tax': tax,
    'total': total,
    'cash': cash,
    'card': card,
    'method': method,
    'cashierId': cashierId,
    'cashierName': cashierName,
    'authorisedBy': authorisedBy,
    'reason': reason,
  };

  factory RefundRecord.fromJson(Map<String, dynamic> j) => RefundRecord(
    number: asInt(j['number']),
    saleNumber: asInt(j['saleNumber']),
    at: asDate(j['at']),
    lines: (j['lines'] as List? ?? [])
        .map((e) => SaleLine.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    subtotal: asDouble(j['subtotal']),
    tax: asDouble(j['tax']),
    total: asDouble(j['total']),
    cash: asDouble(j['cash']),
    card: asDouble(j['card']),
    method: asString(j['method']).isEmpty ? 'Cash' : asString(j['method']),
    cashierId: asString(j['cashierId']),
    cashierName: asString(j['cashierName']),
    authorisedBy: asString(j['authorisedBy']),
    reason: j['reason'] as String?,
  );
}

class HeldSale {
  String id;
  String label;
  DateTime at;
  List<SaleLine> lines;
  String cashierId;
  String cashierName;
  DateTime? staleLoggedAt;

  HeldSale({
    required this.id,
    this.label = '',
    required this.at,
    required this.lines,
    required this.cashierId,
    required this.cashierName,
    this.staleLoggedAt,
  });

  double get total => round2(lines.fold(0, (a, l) => a + l.total));
  double get itemCount => lines.fold(0, (a, l) => a + l.qty);

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'at': at.toIso8601String(),
    'lines': lines.map((l) => l.toJson()).toList(),
    'cashierId': cashierId,
    'cashierName': cashierName,
    'staleLoggedAt': staleLoggedAt?.toIso8601String(),
  };

  factory HeldSale.fromJson(Map<String, dynamic> j) => HeldSale(
    id: asString(j['id']).isEmpty ? newId() : asString(j['id']),
    label: asString(j['label']),
    at: asDate(j['at']),
    lines: (j['lines'] as List? ?? [])
        .map((e) => SaleLine.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    cashierId: asString(j['cashierId']),
    cashierName: asString(j['cashierName']),
    staleLoggedAt: j['staleLoggedAt'] == null
        ? null
        : asDate(j['staleLoggedAt']),
  );
}

/// ------------------------------------------------------------------- audit

class AuditEntry {
  DateTime at;
  String kind;
  String title;
  String detail;
  String? productId;
  String? by;
  double? before;
  double? after;

  AuditEntry({
    required this.at,
    required this.kind,
    required this.title,
    this.detail = '',
    this.productId,
    this.by,
    this.before,
    this.after,
  });

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'kind': kind,
    'title': title,
    'detail': detail,
    'productId': productId,
    'by': by,
    'before': before,
    'after': after,
  };

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
    at: asDate(j['at']),
    kind: asString(j['kind']),
    title: asString(j['title']),
    detail: asString(j['detail']),
    productId: j['productId'] as String?,
    by: j['by'] as String?,
    before: j['before'] == null ? null : asDouble(j['before']),
    after: j['after'] == null ? null : asDouble(j['after']),
  );
}

class StockSnapshot {
  String date;
  DateTime at;
  Map<String, double> stock;

  StockSnapshot({required this.date, required this.at, required this.stock});

  Map<String, dynamic> toJson() => {
    'date': date,
    'at': at.toIso8601String(),
    'stock': stock,
  };

  factory StockSnapshot.fromJson(Map<String, dynamic> j) => StockSnapshot(
    date: asString(j['date']),
    at: asDate(j['at']),
    stock:
        (j['stock'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), asDouble(v)),
        ) ??
        {},
  );
}

/// -------------------------------------------------------------- appearance

class CustomTheme {
  String name;
  int accent;
  int night;

  CustomTheme({required this.name, required this.accent, required this.night});

  Map<String, dynamic> toJson() => {
    'name': name,
    'accent': accent,
    'night': night,
  };

  factory CustomTheme.fromJson(Map<String, dynamic> j) => CustomTheme(
    name: asString(j['name']).isEmpty ? 'My theme' : asString(j['name']),
    accent: asInt(j['accent']),
    night: asInt(j['night']),
  );
}

class Appearance {
  String themeId;
  int fontIndex;
  double textScale;
  String navPosition;
  bool dockNav;

  /// `glass` is the layered aurora-glass look. `matte` keeps the same layout
  /// but paints opaque, near-black surfaces with no blur or colour reflection.
  String surfaceStyle;
  List<CustomTheme> customs;

  Appearance({
    this.themeId = 'teal',
    this.fontIndex = 0,
    this.textScale = 1,
    this.navPosition = 'side',
    this.dockNav = false,
    this.surfaceStyle = 'glass',
    List<CustomTheme>? customs,
  }) : customs =
           customs ??
           [
             CustomTheme(
               name: 'My Theme 1',
               accent: 0xFF2DD4BF,
               night: 0xFF05110F,
             ),
             CustomTheme(
               name: 'My Theme 2',
               accent: 0xFF9B8CFF,
               night: 0xFF0C0918,
             ),
             CustomTheme(
               name: 'My Theme 3',
               accent: 0xFFFFB26B,
               night: 0xFF160F08,
             ),
           ];

  Map<String, dynamic> toJson() => {
    'themeId': themeId,
    'fontIndex': fontIndex,
    'textScale': textScale,
    'navPosition': navPosition,
    'dockNav': dockNav,
    'surfaceStyle': surfaceStyle,
    'customs': customs.map((c) => c.toJson()).toList(),
  };

  factory Appearance.fromJson(Map<String, dynamic> j) {
    final list = (j['customs'] as List? ?? [])
        .map((e) => CustomTheme.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return Appearance(
      themeId: asString(j['themeId']).isEmpty ? 'teal' : asString(j['themeId']),
      fontIndex: asInt(j['fontIndex']).clamp(0, 8),
      textScale: asDouble(j['textScale']) == 0 ? 1 : asDouble(j['textScale']),
      navPosition: asString(j['navPosition']) == 'top' ? 'top' : 'side',
      dockNav: j['dockNav'] == true,
      surfaceStyle: asString(j['surfaceStyle']) == 'matte' ? 'matte' : 'glass',
      customs: list.length == 3
          ? list
          : [...list, ...(Appearance().customs.skip(list.length))],
    );
  }
}

/// ---------------------------------------------------------------- settings

class ShopInfo {
  String name;
  String address;
  String phone;
  String currency;
  double taxRate;
  double lowStock;
  String receiptFooter;

  ShopInfo({
    this.name = 'Sora PoS',
    this.address = '',
    this.phone = '',
    this.currency = 'R',
    this.taxRate = 0,
    this.lowStock = 5,
    this.receiptFooter = 'Thank you for shopping with us.',
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'phone': phone,
    'currency': currency,
    'taxRate': taxRate,
    'lowStock': lowStock,
    'receiptFooter': receiptFooter,
  };

  factory ShopInfo.fromJson(Map<String, dynamic> j) => ShopInfo(
    name: asString(j['name']).isEmpty ? 'Sora PoS' : asString(j['name']),
    address: asString(j['address']),
    phone: asString(j['phone']),
    currency: asString(j['currency']).isEmpty ? 'R' : asString(j['currency']),
    taxRate: asDouble(j['taxRate']),
    lowStock: asDouble(j['lowStock']) == 0 ? 5 : asDouble(j['lowStock']),
    receiptFooter: asString(j['receiptFooter']),
  );
}

class ShopSettings {
  bool chime;
  bool cutPaper;
  bool autoEmail;
  bool autoBackups;
  String backupFrequency;
  String receiptPrinter;
  String emailAddress;
  String emailTime;
  String? lastReportSentDate;
  List<String> pendingReports;
  bool demo;
  double tillPanelFraction;
  String tillRightView;

  ShopSettings({
    this.chime = true,
    this.cutPaper = false,
    this.autoEmail = false,
    this.autoBackups = true,
    this.backupFrequency = 'weekly',
    this.receiptPrinter = '',
    this.emailAddress = '',
    this.emailTime = '17:30',
    this.lastReportSentDate,
    List<String>? pendingReports,
    this.demo = false,
    this.tillPanelFraction = 0.34,
    this.tillRightView = 'cart',
  }) : pendingReports = pendingReports ?? [];

  Map<String, dynamic> toJson() => {
    'chime': chime,
    'cutPaper': cutPaper,
    'autoEmail': autoEmail,
    'autoBackups': autoBackups,
    'backupFrequency': backupFrequency,
    'receiptPrinter': receiptPrinter,
    'emailAddress': emailAddress,
    'emailTime': emailTime,
    'lastReportSentDate': lastReportSentDate,
    'pendingReports': pendingReports,
    'demo': demo,
    'tillPanelFraction': tillPanelFraction,
    'tillRightView': tillRightView,
  };

  factory ShopSettings.fromJson(Map<String, dynamic> j) => ShopSettings(
    chime: j['chime'] != false,
    cutPaper: j['cutPaper'] == true,
    autoEmail: j['autoEmail'] == true,
    autoBackups: j['autoBackups'] != false,
    backupFrequency: asString(j['backupFrequency']).isEmpty
        ? 'weekly'
        : asString(j['backupFrequency']),
    receiptPrinter: asString(j['receiptPrinter']),
    emailAddress: asString(j['emailAddress']),
    emailTime: asString(j['emailTime']).isEmpty
        ? '17:30'
        : asString(j['emailTime']),
    lastReportSentDate: j['lastReportSentDate'] as String?,
    pendingReports: (j['pendingReports'] as List? ?? [])
        .map((e) => e.toString())
        .toList(),
    demo: j['demo'] == true,
    tillPanelFraction:
        (asDouble(j['tillPanelFraction']) == 0
                ? 0.34
                : asDouble(j['tillPanelFraction']))
            .clamp(0.28, 1.0)
            .toDouble(),
    tillRightView: asString(j['tillRightView']) == 'receipt'
        ? 'receipt'
        : 'cart',
  );
}

class ShortcutBinding {
  String action;
  String keys;
  bool hold;

  ShortcutBinding({
    required this.action,
    required this.keys,
    this.hold = false,
  });

  Map<String, dynamic> toJson() => {
    'action': action,
    'keys': keys,
    'hold': hold,
  };

  factory ShortcutBinding.fromJson(Map<String, dynamic> j) => ShortcutBinding(
    action: asString(j['action']),
    keys: asString(j['keys']),
    hold: j['hold'] == true,
  );
}

class ShortcutAction {
  final String id;
  final String label;
  final String group;
  const ShortcutAction(this.id, this.label, this.group);
}

const shortcutActions = <ShortcutAction>[
  ShortcutAction('go.till', 'Go to the Till', 'Screens'),
  ShortcutAction('go.stock', 'Go to Stock', 'Screens'),
  ShortcutAction('go.ledger', 'Go to the Ledger', 'Screens'),
  ShortcutAction('go.overview', 'Go to Overview', 'Screens'),
  ShortcutAction('go.reports', 'Go to Reports', 'Screens'),
  ShortcutAction('go.setup', 'Go to Setup', 'Screens'),
  ShortcutAction('focus.search', 'Jump to the scan/search box', 'Till'),
  ShortcutAction('pay', 'Take payment', 'Till'),
  ShortcutAction('hold', 'Hold the sale', 'Till'),
  ShortcutAction('toggle.products', 'Hide or show the product list', 'Till'),
  ShortcutAction('add.product', 'Add a product', 'Stock'),
  ShortcutAction('clear.filter', 'Clear the Stock filter', 'Stock'),
  ShortcutAction('delete.ticked', 'Delete ticked products', 'Stock'),
  ShortcutAction('email.report', 'Email the day report', 'Reports'),
];

Map<String, ShortcutBinding> defaultShortcuts() => {
  'go.till': ShortcutBinding(action: 'go.till', keys: 'F1'),
  'go.stock': ShortcutBinding(action: 'go.stock', keys: 'F2'),
  'go.ledger': ShortcutBinding(action: 'go.ledger', keys: 'F3'),
  'go.overview': ShortcutBinding(action: 'go.overview', keys: 'F4'),
  'go.reports': ShortcutBinding(action: 'go.reports', keys: 'F5'),
  'go.setup': ShortcutBinding(action: 'go.setup', keys: 'F6'),
  'focus.search': ShortcutBinding(action: 'focus.search', keys: 'F7'),
  'pay': ShortcutBinding(action: 'pay', keys: 'F8'),
  'hold': ShortcutBinding(action: 'hold', keys: 'F9'),
  'email.report': ShortcutBinding(action: 'email.report', keys: 'F10'),
  'toggle.products': ShortcutBinding(action: 'toggle.products', keys: 'F11'),
  'add.product': ShortcutBinding(action: 'add.product', keys: 'F12'),
  'clear.filter': ShortcutBinding(action: 'clear.filter', keys: ''),
  'delete.ticked': ShortcutBinding(action: 'delete.ticked', keys: ''),
};

/// -------------------------------------------------------------------- data

class AppData {
  int version;
  ShopInfo shop;
  ShopSettings settings;
  Appearance appearance;
  List<Product> products;
  List<Category> categories;
  List<Staff> staff;
  List<Sale> sales;
  List<RefundRecord> refunds;
  List<HeldSale> holds;
  List<AuditEntry> audit;
  List<StockSnapshot> snapshots;
  Map<String, ShortcutBinding> shortcuts;
  int nextNumber;

  AppData({
    this.version = 1,
    ShopInfo? shop,
    ShopSettings? settings,
    Appearance? appearance,
    List<Product>? products,
    List<Category>? categories,
    List<Staff>? staff,
    List<Sale>? sales,
    List<RefundRecord>? refunds,
    List<HeldSale>? holds,
    List<AuditEntry>? audit,
    List<StockSnapshot>? snapshots,
    Map<String, ShortcutBinding>? shortcuts,
    this.nextNumber = 1001,
  }) : shop = shop ?? ShopInfo(),
       settings = settings ?? ShopSettings(),
       appearance = appearance ?? Appearance(),
       products = products ?? [],
       categories = categories ?? [],
       staff = staff ?? [],
       sales = sales ?? [],
       refunds = refunds ?? [],
       holds = holds ?? [],
       audit = audit ?? [],
       snapshots = snapshots ?? [],
       shortcuts = shortcuts ?? defaultShortcuts();

  Map<String, dynamic> toJson() => {
    'version': version,
    'shop': shop.toJson(),
    'settings': settings.toJson(),
    'appearance': appearance.toJson(),
    'products': products.map((p) => p.toJson()).toList(),
    'categories': categories.map((c) => c.toJson()).toList(),
    'staff': staff.map((s) => s.toJson()).toList(),
    'sales': sales.map((s) => s.toJson()).toList(),
    'refunds': refunds.map((r) => r.toJson()).toList(),
    'holds': holds.map((h) => h.toJson()).toList(),
    'audit': audit.map((a) => a.toJson()).toList(),
    'snapshots': snapshots.map((s) => s.toJson()).toList(),
    'shortcuts': shortcuts.map((k, v) => MapEntry(k, v.toJson())),
    'nextNumber': nextNumber,
  };

  factory AppData.fromJson(Map<String, dynamic> j) {
    final storedShortcuts = <String, ShortcutBinding>{};
    if (j['shortcuts'] is Map) {
      (j['shortcuts'] as Map).forEach((k, v) {
        if (v is Map) {
          storedShortcuts[k.toString()] = ShortcutBinding.fromJson(
            Map<String, dynamic>.from(v),
          );
        }
      });
    }
    final shorts = defaultShortcuts();
    storedShortcuts.forEach((k, v) {
      if (shorts.containsKey(k)) shorts[k] = v;
    });
    return AppData(
      version: asInt(j['version']),
      shop: ShopInfo.fromJson(
        Map<String, dynamic>.from(j['shop'] as Map? ?? {}),
      ),
      settings: ShopSettings.fromJson(
        Map<String, dynamic>.from(j['settings'] as Map? ?? {}),
      ),
      appearance: Appearance.fromJson(
        Map<String, dynamic>.from(j['appearance'] as Map? ?? {}),
      ),
      products: (j['products'] as List? ?? [])
          .map((e) => Product.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      categories: (j['categories'] as List? ?? [])
          .map((e) => Category.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      staff: (j['staff'] as List? ?? [])
          .map((e) => Staff.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      sales: (j['sales'] as List? ?? [])
          .map((e) => Sale.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      refunds: (j['refunds'] as List? ?? [])
          .map((e) => RefundRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      holds: (j['holds'] as List? ?? [])
          .map((e) => HeldSale.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      audit: (j['audit'] as List? ?? [])
          .map((e) => AuditEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      snapshots: (j['snapshots'] as List? ?? [])
          .map((e) => StockSnapshot.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      shortcuts: shorts,
      nextNumber: asInt(j['nextNumber']) < 1001 ? 1001 : asInt(j['nextNumber']),
    );
  }
}
