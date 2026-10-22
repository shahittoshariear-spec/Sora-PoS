import 'package:flutter/foundation.dart';

import 'models.dart';

/// The sale being built, kept above the screens so checking the stock room
/// or the ledger never loses a customer's basket.
class CartController extends ChangeNotifier {
  final List<SaleLine> _lines = [];

  List<SaleLine> get lines => List.unmodifiable(_lines);
  bool get isEmpty => _lines.isEmpty;
  int get lineCount => _lines.length;

  double get itemCount => _lines.fold(0, (a, l) => a + l.qty);

  void add(Product product, {double qty = 1}) {
    final i = _lines.indexWhere((l) => l.productId == product.id);
    if (i == -1) {
      _lines.add(SaleLine(
        productId: product.id,
        name: product.name,
        sku: product.sku,
        unitPrice: product.price,
        cost: product.cost,
        qty: qty,
      ));
    } else {
      _lines[i].qty += qty;
    }
    notifyListeners();
  }

  void addLine(SaleLine line) {
    final i = _lines.indexWhere((l) => l.productId == line.productId);
    if (i == -1) {
      _lines.add(line);
    } else {
      _lines[i].qty += line.qty;
    }
    notifyListeners();
  }

  void remove(String productId) {
    _lines.removeWhere((l) => l.productId == productId);
    notifyListeners();
  }

  void setQty(String productId, double qty) {
    final i = _lines.indexWhere((l) => l.productId == productId);
    if (i == -1) return;
    if (qty <= 0) {
      _lines.removeAt(i);
    } else {
      _lines[i].qty = qty;
    }
    notifyListeners();
  }

  void bump(String productId, double delta) {
    final i = _lines.indexWhere((l) => l.productId == productId);
    if (i == -1) return;
    setQty(productId, _lines[i].qty + delta);
  }

  void setUnitPrice(String productId, double price) {
    final i = _lines.indexWhere((l) => l.productId == productId);
    if (i == -1) return;
    _lines[i].unitPrice = price;
    notifyListeners();
  }

  void replace(List<SaleLine> lines) {
    _lines
      ..clear()
      ..addAll(lines);
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }
}
