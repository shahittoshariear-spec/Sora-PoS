import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' hide Category;

import 'analytics.dart';
import 'demo.dart';
import 'format.dart';
import 'models.dart';
import 'services/native.dart';
import 'services/paths.dart';

class StoreException implements Exception {
  final String message;
  StoreException(this.message);
  @override
  String toString() => message;
}

class ImportResult {
  final int added;
  final int updated;
  const ImportResult(this.added, this.updated);
}

/// The shop's single source of truth. Everything is kept in one JSON file,
/// written atomically, with the newest twelve automatic backups beside it.
class Store extends ChangeNotifier {
  AppData data = AppData();
  Staff? current;
  bool loaded = false;
  String? notice;

  late Directory rootDir;
  late Directory backupDir;
  late Directory journalDir;
  late File dataFile;

  Timer? _saveTimer;
  Timer? _ticker;
  Future<void> _writeQueue = Future.value();
  DateTime _lastBackupCheck = DateTime.fromMillisecondsSinceEpoch(0);

  String get currency => data.shop.currency;
  String fmt(double value) => money(value, currency);
  bool get isDemo => data.settings.demo;

  Staff? get owner {
    for (final s in data.staff) {
      if (s.role == Role.owner) return s;
    }
    return null;
  }

  Future<void> init() async {
    rootDir = soraDataDirectory();
    backupDir = Directory(joinPath(rootDir.path, 'backups'));
    journalDir = Directory(joinPath(rootDir.path, 'journals'));
    await rootDir.create(recursive: true);
    await backupDir.create(recursive: true);
    await journalDir.create(recursive: true);
    dataFile = File(joinPath(rootDir.path, 'sora-pos-data.json'));

    if (await dataFile.exists()) {
      try {
        final raw = await dataFile.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          data = AppData.fromJson(decoded);
        } else {
          throw const FormatException('The data file is not a Sora document.');
        }
      } catch (e) {
        final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
        try {
          await dataFile.rename('${dataFile.path}.bak-$stamp');
        } catch (_) {}
        data = AppData();
        notice = 'The old data file could not be read, so it was set aside and a fresh shop started.';
      }
    }

    final wantsDemo =
        const bool.fromEnvironment('SORA_DEMO') ||
        Platform.environment['SORA_DEMO'] == '1';
    if (data.staff.isEmpty && wantsDemo) {
      data = buildDemoData();
      current = owner;
      await saveNow();
    } else if (data.settings.demo && data.staff.isNotEmpty) {
      current = owner;
    }

    loaded = true;
    notifyListeners();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    unawaited(checkAutoBackup());
  }

  void _tick() {
    if (DateTime.now().difference(_lastBackupCheck).inMinutes >= 5) {
      _lastBackupCheck = DateTime.now();
      unawaited(checkAutoBackup());
    }
  }

  // ------------------------------------------------------------- lifecycle

  void changed() {
    notifyListeners();
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 180), () {
      unawaited(saveNow());
    });
  }

  Future<void> saveNow() {
    _saveTimer?.cancel();
    _writeQueue = _writeQueue.then((_) => _writeFile()).catchError((Object e) {
      notice = 'Could not save the shop: $e';
      notifyListeners();
    });
    return _writeQueue;
  }

  Future<void> _writeFile() async {
    await rootDir.create(recursive: true);
    final text = const JsonEncoder.withIndent('  ').convert(data.toJson());
    final tmp = File('${dataFile.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    try {
      await tmp.rename(dataFile.path);
    } on FileSystemException {
      final old = File('${dataFile.path}.old');
      if (await dataFile.exists()) {
        if (await old.exists()) await old.delete();
        await dataFile.rename(old.path);
      }
      await tmp.rename(dataFile.path);
      if (await old.exists()) await old.delete();
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------ auth

  Staff? signIn(String staffId, String password) {
    for (final s in data.staff) {
      if (s.id == staffId && s.matches(password)) {
        current = s;
        notifyListeners();
        return s;
      }
    }
    return null;
  }

  void signOut() {
    current = null;
    notifyListeners();
  }

  /// An owner or manager, by password, for approving something a cashier
  /// asked for. The till stays signed in as the cashier.
  Staff? approve(String password) {
    for (final s in data.staff) {
      if (s.role != Role.cashier && s.matches(password)) return s;
    }
    return null;
  }

  Staff? staffByName(String name) {
    for (final s in data.staff) {
      if (s.name == name) return s;
    }
    return null;
  }

  bool get isOwner => current?.role == Role.owner;
  bool get isManagerOrOwner =>
      current?.role == Role.manager || current?.role == Role.owner;

  bool mayOpen(String section) {
    final role = current?.role;
    if (role == null) return false;
    return switch (section) {
      'till' => true,
      'stock' || 'ledger' => role == Role.manager || role == Role.owner,
      'overview' || 'reports' || 'setup' => role == Role.owner,
      _ => false,
    };
  }

  /// Section-level approvals are obsolete: a role sees exactly its sections.
  /// In-sale actions (price override, void, refund) still ask a manager/owner.
  bool needsApproval(String section) => false;

  // ----------------------------------------------------------------- audit

  void recordAudit({
    required String kind,
    required String title,
    String detail = '',
    String? productId,
    double? before,
    double? after,
    String? by,
  }) {
    data.audit.add(
      AuditEntry(
        at: DateTime.now(),
        kind: kind,
        title: title,
        detail: detail,
        productId: productId,
        by: by ?? current?.name ?? 'System',
        before: before,
        after: after,
      ),
    );
    if (data.audit.length > 5000) {
      data.audit.removeRange(0, data.audit.length - 5000);
    }
  }

  // -------------------------------------------------------------- products

  Product? productById(String id) {
    for (final p in data.products) {
      if (p.id == id) return p;
    }
    return null;
  }

  String categoryName(String id) {
    for (final c in data.categories) {
      if (c.id == id) return c.name;
    }
    return 'Uncategorised';
  }

  Future<void> upsertProduct(Product product) async {
    final i = data.products.indexWhere((p) => p.id == product.id);
    if (i == -1) {
      product.updatedAt = DateTime.now();
      data.products.add(product);
      recordAudit(
        kind: 'product_add',
        title: 'Product added',
        detail: '${product.name} · ${numText(product.stock)} on the shelf',
        productId: product.id,
        after: product.stock,
      );
    } else {
      final old = data.products[i];
      product.createdAt = old.createdAt;
      product.updatedAt = DateTime.now();
      if ((old.stock - product.stock).abs() > 0.0001) {
        recordAudit(
          kind: 'stock_edit',
          title: 'Stock typed over by hand',
          detail:
              '${old.name} · ${numText(old.stock)} → ${numText(product.stock)}',
          productId: old.id,
          before: old.stock,
          after: product.stock,
        );
      }
      if ((old.price - product.price).abs() > 0.001) {
        recordAudit(
          kind: 'price_change',
          title: 'Price changed in Stock',
          detail: '${old.name} · ${fmt(old.price)} → ${fmt(product.price)}',
          productId: old.id,
          before: old.price,
          after: product.price,
        );
      }
      if ((old.cost - product.cost).abs() > 0.001) {
        recordAudit(
          kind: 'cost_change',
          title: 'Cost changed in Stock',
          detail: '${old.name} · ${fmt(old.cost)} → ${fmt(product.cost)}',
          productId: old.id,
          before: old.cost,
          after: product.cost,
        );
      }
      data.products[i] = product;
    }
    changed();
  }

  Future<void> deleteProduct(String id) async {
    final p = productById(id);
    if (p == null) return;
    data.products.removeWhere((e) => e.id == id);
    recordAudit(
      kind: 'product_delete',
      title: 'Product deleted',
      detail: '${p.name} · ${numText(p.stock)} went with it',
      productId: p.id,
      before: p.stock,
    );
    changed();
  }

  Future<void> deleteProducts(Iterable<String> ids) async {
    for (final id in ids.toList()) {
      await deleteProduct(id);
    }
  }

  // ------------------------------------------------------------ categories

  Future<void> addCategory(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw StoreException('Give the category a name.');
    if (data.categories.any(
      (c) => c.name.toLowerCase() == clean.toLowerCase(),
    )) {
      throw StoreException('There is already a category called “$clean”.');
    }
    data.categories.add(Category(id: newId(), name: clean));
    changed();
  }

  Future<void> renameCategory(String id, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw StoreException('Give the category a name.');
    if (data.categories.any(
      (c) => c.id != id && c.name.toLowerCase() == clean.toLowerCase(),
    )) {
      throw StoreException('There is already a category called “$clean”.');
    }
    final c = data.categories.firstWhere(
      (e) => e.id == id,
      orElse: () => Category(id: id, name: clean),
    );
    c.name = clean;
    if (!data.categories.any((e) => e.id == id)) data.categories.add(c);
    changed();
  }

  Future<int> deleteCategory(String id, {String? moveTo}) async {
    if (data.categories.length <= 1) {
      throw StoreException('The last category cannot be removed.');
    }
    final affected = data.products.where((p) => p.categoryId == id).toList();
    if (affected.isNotEmpty && (moveTo == null || moveTo == id)) {
      throw StoreException('Choose where those products should move first.');
    }
    for (final p in affected) {
      p.categoryId = moveTo!;
    }
    data.categories.removeWhere((c) => c.id == id);
    changed();
    return affected.length;
  }

  // ----------------------------------------------------------------- staff

  Future<Staff> addStaff({
    required String name,
    required String password,
    required Role role,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) throw StoreException('Give this person a name.');
    if (password.length < 4)
      throw StoreException('Use at least four characters for the password.');
    if (data.staff.any((s) => s.name.toLowerCase() == clean.toLowerCase())) {
      throw StoreException('Someone in the shop is already called “$clean”.');
    }
    final salt = Passwords.newSalt();
    final s = Staff(
      id: newId(),
      name: clean,
      role: role,
      salt: salt,
      passwordHash: Passwords.hash(password, salt),
    );
    data.staff.add(s);
    changed();
    return s;
  }

  Future<void> updateStaff(
    String id, {
    String? name,
    Role? role,
    String? password,
  }) async {
    final s = data.staff.firstWhere(
      (e) => e.id == id,
      orElse: () => throw StoreException('That person is no longer here.'),
    );
    final clean = (name ?? s.name).trim();
    if (clean.isEmpty) throw StoreException('Give this person a name.');
    if (data.staff.any(
      (o) => o.id != id && o.name.toLowerCase() == clean.toLowerCase(),
    )) {
      throw StoreException('Someone in the shop is already called “$clean”.');
    }
    final nextRole = role ?? s.role;
    if (s.role == Role.owner && nextRole != Role.owner) {
      final owners = data.staff.where((e) => e.role == Role.owner).length;
      if (owners <= 1)
        throw StoreException('There must always be at least one owner.');
    }
    if (password != null && password.isNotEmpty) {
      if (password.length < 4)
        throw StoreException('Use at least four characters for the password.');
      s.salt = Passwords.newSalt();
      s.passwordHash = Passwords.hash(password, s.salt);
    }
    s.name = clean;
    s.role = nextRole;
    if (current?.id == s.id) current = s;
    changed();
  }

  Future<void> deleteStaff(String id) async {
    final s = data.staff.firstWhere(
      (e) => e.id == id,
      orElse: () => throw StoreException('That person is no longer here.'),
    );
    if (s.role == Role.owner &&
        data.staff.where((e) => e.role == Role.owner).length <= 1) {
      throw StoreException('There must always be at least one owner.');
    }
    data.staff.removeWhere((e) => e.id == id);
    if (current?.id == id) current = null;
    changed();
  }

  // ------------------------------------------------------------------ till

  CartTotals cartTotals(List<SaleLine> lines) {
    final subtotal = round2(lines.fold(0.0, (a, l) => a + l.total));
    final tax = round2(subtotal * data.shop.taxRate / 100);
    final items = lines.fold(0.0, (a, l) => a + l.qty);
    return CartTotals(subtotal, tax, round2(subtotal + tax), items);
  }

  Future<Sale> completeSale({
    required List<SaleLine> lines,
    required double card,
    required double cashTendered,
    String? note,
  }) async {
    final staff = current;
    if (staff == null) throw StoreException('Sign in before taking a payment.');
    if (lines.isEmpty) throw StoreException('The sale is empty.');
    final totals = cartTotals(lines);
    final appliedCard = round2(min(max(0, card), totals.total));
    final appliedCash = round2(totals.total - appliedCard);
    if (cashTendered + appliedCard < totals.total - 0.009 && appliedCash > 0) {
      throw StoreException('The payment does not cover the sale.');
    }
    final change = round2(max(0, cashTendered - appliedCash));
    final sale = Sale(
      number: data.nextNumber++,
      at: DateTime.now(),
      lines: List.of(lines),
      subtotal: totals.subtotal,
      tax: totals.tax,
      total: totals.total,
      cash: appliedCash,
      card: appliedCard,
      cashTendered: cashTendered,
      change: change,
      cashierId: staff.id,
      cashierName: staff.name,
      note: note,
    );
    data.sales.add(sale);
    for (final line in lines) {
      final p = productById(line.productId);
      if (p != null) {
        p.stock = round2(p.stock - line.qty);
        p.updatedAt = sale.at;
      }
    }
    changed();
    await saveNow();
    return sale;
  }

  Map<String, double> refundedQuantities(int saleNumber) {
    final out = <String, double>{};
    for (final r in data.refunds) {
      if (r.saleNumber != saleNumber) continue;
      for (final l in r.lines) {
        out[l.productId] = (out[l.productId] ?? 0) + l.qty;
      }
    }
    return out;
  }

  Map<String, double> availableForRefund(Sale sale) {
    final refunded = refundedQuantities(sale.number);
    final out = <String, double>{};
    for (final l in sale.lines) {
      final left = l.qty - (refunded[l.productId] ?? 0);
      if (left > 0.0001) out[l.productId] = left;
    }
    return out;
  }

  CartTotals refundTotals(Sale sale, Map<String, double> quantities) {
    double subtotal = 0;
    double items = 0;
    for (final l in sale.lines) {
      final q = quantities[l.productId] ?? 0;
      if (q <= 0) continue;
      subtotal += l.unitPrice * q;
      items += q;
    }
    subtotal = round2(subtotal);
    final ratio = sale.subtotal == 0
        ? data.shop.taxRate / 100
        : sale.tax / sale.subtotal;
    final tax = round2(subtotal * ratio);
    return CartTotals(subtotal, tax, round2(subtotal + tax), items);
  }

  Future<RefundRecord> refundSale({
    required Sale sale,
    required Map<String, double> quantities,
    required String method,
    required double cash,
    required double card,
    Staff? approvedBy,
    String? reason,
  }) async {
    final staff = current;
    if (staff == null) throw StoreException('Sign in first.');
    final available = availableForRefund(sale);
    final lines = <SaleLine>[];
    for (final l in sale.lines) {
      final want = min(
        quantities[l.productId] ?? 0,
        available[l.productId] ?? 0,
      );
      if (want <= 0) continue;
      lines.add(l.copyWith(qty: want));
    }
    if (lines.isEmpty)
      throw StoreException('Choose at least one item to refund.');
    final totals = refundTotals(sale, {
      for (final l in lines) l.productId: l.qty,
    });
    final refund = RefundRecord(
      number: data.nextNumber++,
      saleNumber: sale.number,
      at: DateTime.now(),
      lines: lines,
      subtotal: totals.subtotal,
      tax: totals.tax,
      total: totals.total,
      cash: round2(cash),
      card: round2(card),
      method: method,
      cashierId: staff.id,
      cashierName: staff.name,
      authorisedBy: approvedBy?.name ?? '',
      reason: reason,
    );
    data.refunds.add(refund);
    for (final l in lines) {
      final p = productById(l.productId);
      if (p != null) {
        p.stock = round2(p.stock + l.qty);
        p.updatedAt = refund.at;
      }
    }
    changed();
    await saveNow();
    return refund;
  }

  Future<void> voidSale(Sale sale, {Staff? approvedBy}) async {
    final staff = current;
    if (staff == null) throw StoreException('Sign in first.');
    if (sale.voided) throw StoreException('That sale is already void.');
    final refunded = refundedQuantities(sale.number);
    sale.voided = true;
    sale.voidedById = staff.id;
    sale.voidedByName = staff.name;
    sale.voidedAt = DateTime.now();
    for (final l in sale.lines) {
      final left = l.qty - (refunded[l.productId] ?? 0);
      if (left <= 0) continue;
      final p = productById(l.productId);
      if (p != null) {
        p.stock = round2(p.stock + left);
        p.updatedAt = DateTime.now();
      }
    }
    if (approvedBy != null) {
      recordAudit(
        kind: 'void',
        title: 'Sale voided',
        detail: 'Sale #${sale.number} · approved by ${approvedBy.name}',
        by: staff.name,
      );
    }
    changed();
    await saveNow();
  }

  Future<HeldSale> holdSale(List<SaleLine> lines, {String label = ''}) async {
    final staff = current;
    if (staff == null) throw StoreException('Sign in first.');
    if (lines.isEmpty) throw StoreException('There is nothing to hold.');
    final hold = HeldSale(
      id: newId(),
      label: label.trim(),
      at: DateTime.now(),
      lines: List.of(lines),
      cashierId: staff.id,
      cashierName: staff.name,
    );
    data.holds.add(hold);
    changed();
    return hold;
  }

  List<SaleLine> resumeHold(String id) {
    final i = data.holds.indexWhere((h) => h.id == id);
    if (i == -1) return [];
    final hold = data.holds.removeAt(i);
    changed();
    return hold.lines;
  }

  Future<void> discardHold(String id) async {
    final i = data.holds.indexWhere((h) => h.id == id);
    if (i == -1) return;
    final hold = data.holds.removeAt(i);
    final now = DateTime.now();
    recordAudit(
      kind: 'held_discard',
      title: 'A held sale was thrown away',
      detail:
          '${hold.label.isEmpty ? 'Held sale' : hold.label} · held ${timeExact(hold.at)} · thrown away ${timeExact(now)} · waited ${_dwellText(hold.at, now)} · ${numText(hold.itemCount)} items · ${fmt(hold.total)}',
    );
    changed();
  }

  /// Holds that were never resumed or discarded. Logged once per hold, with
  /// no UI hint, so an abandoned sale still reaches the daily watch list.
  void checkAbandonedHolds({Duration after = const Duration(hours: 8)}) {
    final now = DateTime.now();
    var logged = false;
    for (final hold in data.holds) {
      if (hold.staleLoggedAt != null) continue;
      if (now.difference(hold.at) < after) continue;
      hold.staleLoggedAt = now;
      recordAudit(
        kind: 'held_stale',
        title: 'A held sale was never completed',
        detail:
            '${hold.label.isEmpty ? 'Held sale' : hold.label} · held ${timeExact(hold.at)} · still open after ${_dwellText(hold.at, now)} · ${numText(hold.itemCount)} items · ${fmt(hold.total)} · cashier ${hold.cashierName.isEmpty ? 'unknown' : hold.cashierName}',
        by: hold.cashierName.isEmpty ? 'System' : hold.cashierName,
      );
      logged = true;
    }
    if (logged) changed();
  }

  /// Silent record of a line that was on the till and never reached a
  /// completed sale. This is deliberately not surfaced anywhere in the UI.
  void recordCartLinesRemoved(
    List<SaleLine> lines, {
    required List<SaleLine> saleBefore,
    String reason = 'removed from the sale',
  }) {
    if (lines.isEmpty) return;
    final now = DateTime.now();
    final cartValue = cartTotals(saleBefore).total;
    final number = data.nextNumber;
    for (final line in lines) {
      recordAudit(
        kind: 'cart_removed',
        title: 'An item left the till before payment',
        detail:
            '${line.name} · ${numText(line.qty)} × ${fmt(line.unitPrice)} · added ${timeExact(line.addedAt)} · left ${timeExact(now)} · waited ${_dwellText(line.addedAt, now)} · cart ${fmt(cartValue)} · sale #$number · $reason',
        productId: line.productId,
        before: line.qty,
        after: 0,
      );
    }
  }

  void recordCartCleared(
    List<SaleLine> lines, {
    String reason = 'the sale was emptied',
  }) {
    if (lines.isEmpty) return;
    recordCartLinesRemoved(lines, saleBefore: List.of(lines), reason: reason);
  }

  String _dwellText(DateTime from, DateTime to) {
    var seconds = to.difference(from).inSeconds;
    if (seconds < 0) seconds = 0;
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600)
      return '${seconds ~/ 60}m ${(seconds % 60).toString().padLeft(2, '0')}s';
    return '${seconds ~/ 3600}h ${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}m';
  }

  // --------------------------------------------------------------- backups

  List<File> listBackups() {
    if (!backupDir.existsSync()) return [];
    final files = backupDir
        .listSync()
        .whereType<File>()
        .where(
          (f) =>
              f.path.split(Platform.pathSeparator).last.startsWith('sora-pos-'),
        )
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  DateTime? get lastBackupAt {
    final list = listBackups();
    if (list.isEmpty) return null;
    return list.first.statSync().modified;
  }

  Future<File?> backupNow({String reason = 'manual'}) async {
    try {
      await saveNow();
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      await backupDir.create(recursive: true);
      final dest = File(joinPath(backupDir.path, 'sora-pos-$stamp.json'));
      if (await dataFile.exists()) {
        await dataFile.copy(dest.path);
      } else {
        await dest.writeAsString(
          const JsonEncoder.withIndent('  ').convert(data.toJson()),
        );
      }
      _pruneBackups();
      return dest;
    } catch (_) {
      return null;
    }
  }

  void _pruneBackups() {
    final list = listBackups();
    for (var i = 12; i < list.length; i++) {
      try {
        list[i].deleteSync();
      } catch (_) {}
    }
  }

  Future<void> checkAutoBackup() async {
    if (!data.settings.autoBackups) return;
    if (data.settings.backupFrequency == 'off') return;
    final interval = switch (data.settings.backupFrequency) {
      'daily' => const Duration(days: 1),
      'monthly' => const Duration(days: 30),
      _ => const Duration(days: 7),
    };
    final last = lastBackupAt;
    if (last == null || DateTime.now().difference(last) >= interval) {
      await backupNow(reason: 'auto');
    }
  }

  Future<String?> exportBackup() async {
    final path = await NativeCore.saveDialog(
      title: 'Export a Sora backup',
      defaultName: 'sora-pos-backup-${dateKey(DateTime.now())}.json',
      filter: 'Sora backup|*.json',
    );
    if (path == null) return null;
    await saveNow();
    final text = const JsonEncoder.withIndent('  ').convert(data.toJson());
    await File(path).writeAsString(text, flush: true);
    return path;
  }

  Future<String?> importBackup() async {
    final path = await NativeCore.openDialog(
      title: 'Restore a Sora backup',
      filter: 'Sora backup|*.json',
    );
    if (path == null) return null;
    final raw = await File(path).readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>)
      throw StoreException('That file is not a Sora backup.');
    final restored = AppData.fromJson(decoded);
    // Never let a restore go ahead without a copy of what is here now.
    final safety = await backupNow(reason: 'before-restore');
    if (safety == null)
      throw StoreException(
        'Could not take a safety backup, so nothing was restored.',
      );
    data = restored;
    current = null;
    notice = 'Backup restored. Sign in to carry on.';
    await saveNow();
    notifyListeners();
    return path;
  }

  // --------------------------------------------------------------- imports

  Future<ImportResult> applyImportedProducts(
    List<ImportedProduct> items,
  ) async {
    int added = 0, updated = 0;
    for (final item in items) {
      final name = item.name.trim();
      if (name.isEmpty) continue;
      String categoryId = '';
      final catName = item.category.trim().isEmpty
          ? 'General'
          : item.category.trim();
      final existingCat = data.categories
          .where((c) => c.name.toLowerCase() == catName.toLowerCase())
          .toList();
      if (existingCat.isNotEmpty) {
        categoryId = existingCat.first.id;
      } else {
        final cat = Category(id: newId(), name: catName);
        data.categories.add(cat);
        categoryId = cat.id;
      }
      final match = item.sku.trim().isEmpty
          ? null
          : data.products
                .where(
                  (p) => p.sku.toLowerCase() == item.sku.trim().toLowerCase(),
                )
                .toList();
      if (match != null && match.isNotEmpty) {
        final p = match.first;
        p.name = name;
        p.price = item.price;
        p.cost = item.cost;
        p.stock = item.stock;
        p.categoryId = categoryId;
        p.updatedAt = DateTime.now();
        updated++;
      } else {
        data.products.add(
          Product(
            id: newId(),
            name: name,
            sku: item.sku.trim(),
            categoryId: categoryId,
            price: item.price,
            cost: item.cost,
            stock: item.stock,
          ),
        );
        added++;
      }
    }
    recordAudit(
      kind: 'import',
      title: 'Spreadsheet imported',
      detail: '$added added, $updated updated',
    );
    changed();
    await saveNow();
    return ImportResult(added, updated);
  }

  // ----------------------------------------------------------------- email

  Future<String> writeSalesJournal(DateTime day) async {
    final start = startOfDay(day);
    final end = start.add(const Duration(days: 1));
    final sales = data.sales
        .where((s) => !s.at.isBefore(start) && s.at.isBefore(end))
        .toList();
    final refunds = data.refunds
        .where((r) => !r.at.isBefore(start) && r.at.isBefore(end))
        .toList();
    final payload = {
      'shop': data.shop.name,
      'day': dateKey(day),
      'writtenAt': DateTime.now().toIso8601String(),
      'sales': sales.map((s) => s.toJson()).toList(),
      'refunds': refunds.map((r) => r.toJson()).toList(),
    };
    await journalDir.create(recursive: true);
    final file = File(
      joinPath(journalDir.path, 'sales-journal-${dateKey(day)}.json'),
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    _pruneJournals();
    return file.path;
  }

  void _pruneJournals() {
    final files =
        journalDir
            .listSync()
            .whereType<File>()
            .where(
              (f) => f.path
                  .split(Platform.pathSeparator)
                  .last
                  .startsWith('sales-journal-'),
            )
            .toList()
          ..sort((a, b) => b.path.compareTo(a.path));
    for (var i = 400; i < files.length; i++) {
      try {
        files[i].deleteSync();
      } catch (_) {}
    }
  }

  DateTime? get lastReportSent {
    final d = data.settings.lastReportSentDate;
    if (d == null) return null;
    return DateTime.tryParse(d);
  }

  Future<void> markReportSent(DateTime day) async {
    data.settings.lastReportSentDate = dateKey(day);
    data.settings.pendingReports.remove(dateKey(day));
    changed();
    await saveNow();
  }

  /// A picture of the shelf at the moment a report is built. The next report
  /// counts against it, so any movement no sale explains is visible.
  Future<void> captureSnapshot(DateTime day) async {
    final key = dateKey(day);
    final stock = <String, double>{
      for (final p in data.products) p.id: p.stock,
    };
    data.snapshots.removeWhere((s) => s.date == key);
    data.snapshots.add(
      StockSnapshot(date: key, at: DateTime.now(), stock: stock),
    );
    if (data.snapshots.length > 60) {
      data.snapshots.sort((a, b) => a.at.compareTo(b.at));
      data.snapshots.removeRange(0, data.snapshots.length - 60);
    }
    changed();
    await saveNow();
  }

  void queueReport(String dayKey) {
    if (!data.settings.pendingReports.contains(dayKey)) {
      data.settings.pendingReports.add(dayKey);
      changed();
    }
  }

  // ----------------------------------------------------------------- resets

  Future<void> resetSalesAndStock() async {
    final safety = await backupNow(reason: 'before-reset');
    if (safety == null) {
      throw StoreException(
        'The safety backup could not be written, so nothing was reset.',
      );
    }
    data.sales.clear();
    data.refunds.clear();
    data.holds.clear();
    data.snapshots.clear();
    for (final p in data.products) {
      p.stock = 0;
      p.updatedAt = DateTime.now();
    }
    recordAudit(
      kind: 'reset',
      title: 'Sales and stock reset',
      detail:
          'A backup was taken first: ${safety.path.split(Platform.pathSeparator).last}',
    );
    changed();
    await saveNow();
  }

  Future<void> resetEverything() async {
    final safety = await backupNow(reason: 'before-reset');
    if (safety == null) {
      throw StoreException(
        'The safety backup could not be written, so nothing was reset.',
      );
    }
    data = AppData();
    current = null;
    notice = 'The shop is blank again. A backup of everything was kept.';
    await saveNow();
    notifyListeners();
  }

  // -------------------------------------------------------------------- demo

  Future<void> seedDemo({bool autoSignIn = true}) async {
    data = buildDemoData();
    current = autoSignIn ? owner : null;
    loaded = true;
    notice = null;
    await saveNow();
    notifyListeners();
  }

  // ---------------------------------------------------------------- helpers

  List<Product> searchProducts(
    String query, {
    String categoryId = '',
    int limit = 120,
  }) {
    final q = query.trim().toLowerCase();
    final results = <Product>[];
    for (final p in data.products) {
      if (categoryId.isNotEmpty && p.categoryId != categoryId) continue;
      if (q.isNotEmpty &&
          !p.name.toLowerCase().contains(q) &&
          !p.sku.toLowerCase().contains(q) &&
          !p.searchName.toLowerCase().contains(q)) {
        continue;
      }
      results.add(p);
      if (results.length >= limit) break;
    }
    results.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return results;
  }

  int matchCount(String query, {String categoryId = ''}) {
    final q = query.trim().toLowerCase();
    return data.products.where((p) {
      if (categoryId.isNotEmpty && p.categoryId != categoryId) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          p.searchName.toLowerCase().contains(q);
    }).length;
  }

  Product? exactMatch(String code) {
    final q = code.trim().toLowerCase();
    if (q.isEmpty) return null;
    for (final p in data.products) {
      if (p.sku.toLowerCase() == q) return p;
    }
    for (final p in data.products) {
      if (p.searchName.toLowerCase() == q) return p;
    }
    final nameMatches = data.products
        .where((p) => p.name.toLowerCase() == q)
        .toList();
    if (nameMatches.length == 1) return nameMatches.first;
    final contains = data.products
        .where((p) => p.name.toLowerCase().contains(q))
        .toList();
    return contains.length == 1 ? contains.first : null;
  }

  Sale? saleByNumber(int number) {
    for (final s in data.sales) {
      if (s.number == number) return s;
    }
    return null;
  }
}
