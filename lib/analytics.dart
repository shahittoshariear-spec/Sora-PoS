import 'dart:math';

import 'format.dart';
import 'models.dart';

/// All the shop's arithmetic lives here, away from the screens, so the
/// figures on the Overview, the day report and the receipts always agree.
///
/// The overview is a whole-shop view. It is calculated from the sales and
/// refunds themselves, never from a running total, so a void or a refund
/// immediately removes itself from every figure.

enum PeriodTab { day, week, month, year }

extension PeriodTabName on PeriodTab {
  String get label => switch (this) {
        PeriodTab.day => 'Day',
        PeriodTab.week => 'Week',
        PeriodTab.month => 'Month',
        PeriodTab.year => 'Year',
      };
}

DateTime periodStart(PeriodTab tab, DateTime now) => switch (tab) {
      PeriodTab.day => startOfDay(now),
      PeriodTab.week => startOfWeek(now),
      PeriodTab.month => startOfMonth(now),
      PeriodTab.year => startOfYear(now),
    };

DateTime periodEnd(PeriodTab tab, DateTime now) {
  final s = periodStart(tab, now);
  return switch (tab) {
    PeriodTab.day => s.add(const Duration(days: 1)),
    PeriodTab.week => s.add(const Duration(days: 7)),
    PeriodTab.month => DateTime(s.year, s.month + 1, 1),
    PeriodTab.year => DateTime(s.year + 1, 1, 1),
  };
}

DateTime previousPeriodStart(PeriodTab tab, DateTime start) => switch (tab) {
      PeriodTab.day => DateTime(start.year, start.month, start.day - 1),
      PeriodTab.week => start.subtract(const Duration(days: 7)),
      PeriodTab.month => DateTime(start.year, start.month - 1, 1),
      PeriodTab.year => DateTime(start.year - 1, 1, 1),
    };

class PeriodTotals {
  final double sales;
  final double refunds;
  final double tax;
  final double profit;
  final double cash;
  final double card;
  final int transactions;
  final double items;
  final List<Sale> saleList;
  final List<RefundRecord> refundList;

  const PeriodTotals({
    this.sales = 0,
    this.refunds = 0,
    this.tax = 0,
    this.profit = 0,
    this.cash = 0,
    this.card = 0,
    this.transactions = 0,
    this.items = 0,
    this.saleList = const [],
    this.refundList = const [],
  });

  double get net => round2(sales - refunds);
  double get averageSale => transactions == 0 ? 0 : round2(sales / transactions);
  double get expectedDrawer => round2(cash - refundList.fold(0.0, (a, r) => a + r.cash));
}

PeriodTotals totalsBetween(AppData data, DateTime start, DateTime end) {
  final sales = data.sales
      .where((s) => !s.voided && !s.at.isBefore(start) && s.at.isBefore(end))
      .toList();
  final refunds = data.refunds
      .where((r) => !r.at.isBefore(start) && r.at.isBefore(end))
      .toList();

  double subtotal = 0, tax = 0, profit = 0, cash = 0, card = 0, items = 0;
  for (final s in sales) {
    subtotal += s.subtotal;
    tax += s.tax;
    profit += s.grossProfit;
    cash += s.cash;
    card += s.card;
    items += s.itemCount;
  }
  double rTotal = 0, rProfit = 0, rCash = 0, rCard = 0, rItems = 0;
  for (final r in refunds) {
    rTotal += r.total;
    rProfit += round2(r.subtotal - r.cogs);
    rCash += r.cash;
    rCard += r.card;
    rItems += r.itemCount;
  }

  return PeriodTotals(
    sales: round2(subtotal + tax),
    refunds: round2(rTotal),
    tax: round2(tax - refunds.fold(0.0, (a, r) => a + r.tax)),
    profit: round2(profit - rProfit),
    cash: round2(cash - rCash),
    card: round2(card - rCard),
    transactions: sales.length,
    items: items - rItems,
    saleList: sales,
    refundList: refunds,
  );
}

PeriodTotals totalsFor(AppData data, PeriodTab tab, [DateTime? now]) => totalsBetween(
      data,
      periodStart(tab, now ?? DateTime.now()),
      periodEnd(tab, now ?? DateTime.now()),
    );

PeriodTotals totalsForDay(AppData data, DateTime day) =>
    totalsBetween(data, startOfDay(day), startOfDay(day).add(const Duration(days: 1)));

/// ----------------------------------------------------------------- charts

class SeriesPoint {
  final String label;
  final DateTime start;
  final double sales;
  final double profit;
  const SeriesPoint(this.label, this.start, this.sales, this.profit);
}

List<SeriesPoint> chartSeries(AppData data, PeriodTab tab, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final points = <SeriesPoint>[];
  if (tab == PeriodTab.day) {
    final start = startOfDay(n);
    for (int i = 13; i >= 0; i--) {
      final day = start.subtract(Duration(days: i));
      final t = totalsBetween(data, day, day.add(const Duration(days: 1)));
      points.add(SeriesPoint(weekdayShort(day), day, t.sales, t.profit));
    }
  } else if (tab == PeriodTab.week) {
    final start = startOfWeek(n);
    for (int i = 7; i >= 0; i--) {
      final s = start.subtract(Duration(days: 7 * i));
      final t = totalsBetween(data, s, s.add(const Duration(days: 7)));
      points.add(SeriesPoint(dayMonth(s), s, t.sales, t.profit));
    }
  } else if (tab == PeriodTab.month) {
    final nowMonth = DateTime(n.year, n.month, 1);
    for (int i = 11; i >= 0; i--) {
      final s = DateTime(nowMonth.year, nowMonth.month - i, 1);
      final e = DateTime(s.year, s.month + 1, 1);
      final t = totalsBetween(data, s, e);
      points.add(SeriesPoint(DateFormatShort.month(s), s, t.sales, t.profit));
    }
  } else {
    final y = n.year;
    for (int i = 4; i >= 0; i--) {
      final s = DateTime(y - i, 1, 1);
      final e = DateTime(y - i + 1, 1, 1);
      final t = totalsBetween(data, s, e);
      points.add(SeriesPoint('${s.year}', s, t.sales, t.profit));
    }
  }
  return points;
}

class DateFormatShort {
  static String month(DateTime d) =>
      const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1];
}

/// ---------------------------------------------------------------- history

class PeriodRow {
  final String label;
  final DateTime start;
  final PeriodTotals totals;
  const PeriodRow(this.label, this.start, this.totals);
}

List<PeriodRow> periodHistory(AppData data, PeriodTab tab, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final rows = <PeriodRow>[];
  final currentStart = periodStart(tab, n);
  for (int i = 0; i < 13; i++) {
    final DateTime start;
    if (tab == PeriodTab.day) {
      start = DateTime(currentStart.year, currentStart.month, currentStart.day - i);
    } else if (tab == PeriodTab.week) {
      start = currentStart.subtract(Duration(days: 7 * i));
    } else if (tab == PeriodTab.month) {
      start = DateTime(currentStart.year, currentStart.month - i, 1);
    } else {
      start = DateTime(currentStart.year - i, 1, 1);
    }
    final end = switch (tab) {
      PeriodTab.day => start.add(const Duration(days: 1)),
      PeriodTab.week => start.add(const Duration(days: 7)),
      PeriodTab.month => DateTime(start.year, start.month + 1, 1),
      PeriodTab.year => DateTime(start.year + 1, 1, 1),
    };
    final t = totalsBetween(data, start, end);
    final label = switch (tab) {
      PeriodTab.day => i == 0 ? 'Today' : i == 1 ? 'Yesterday' : dateLong(start).split(',').first,
      PeriodTab.week => i == 0 ? 'This week' : '${dayMonth(start)} – ${dayMonth(end.subtract(const Duration(days: 1)))}',
      PeriodTab.month => i == 0 ? 'This month' : monthYear(start),
      PeriodTab.year => '${start.year}',
    };
    rows.add(PeriodRow(label, start, t));
  }
  return rows;
}

/// ------------------------------------------------------------ top sellers

class TopSeller {
  final String name;
  final double qty;
  final double revenue;
  const TopSeller(this.name, this.qty, this.revenue);
}

List<TopSeller> topSellers(AppData data, DateTime start, DateTime end, {int limit = 5}) {
  final map = <String, TopSeller>{};
  for (final s in data.sales) {
    if (s.voided || s.at.isBefore(start) || !s.at.isBefore(end)) continue;
    for (final l in s.lines) {
      final existing = map[l.name];
      map[l.name] = TopSeller(
        l.name,
        (existing?.qty ?? 0) + l.qty,
        round2((existing?.revenue ?? 0) + l.total),
      );
    }
  }
  for (final r in data.refunds) {
    if (r.at.isBefore(start) || !r.at.isBefore(end)) continue;
    for (final l in r.lines) {
      final existing = map[l.name];
      if (existing == null) continue;
      map[l.name] = TopSeller(l.name, existing.qty - l.qty, round2(existing.revenue - l.total));
    }
  }
  final list = map.values.where((v) => v.qty > 0).toList()
    ..sort((a, b) => b.qty.compareTo(a.qty));
  return list.take(limit).toList();
}

/// --------------------------------------------------------- itemised history

class HistoryLine {
  final DateTime at;
  final bool isRefund;
  final int number;
  final int saleNumber;
  final SaleLine line;
  final String payment;
  final String cashier;
  final String? authorisedBy;

  const HistoryLine({
    required this.at,
    required this.isRefund,
    required this.number,
    required this.saleNumber,
    required this.line,
    required this.payment,
    required this.cashier,
    this.authorisedBy,
  });
}

List<HistoryLine> lineHistory(AppData data, {DateTime? day, String query = ''}) {
  final out = <HistoryLine>[];
  final q = query.trim().toLowerCase();
  for (final s in data.sales) {
    if (day != null && (s.at.isBefore(startOfDay(day)) || !s.at.isBefore(startOfDay(day).add(const Duration(days: 1))))) {
      continue;
    }
    for (final l in s.lines) {
      if (q.isNotEmpty && !l.name.toLowerCase().contains(q) && !'${s.number}'.contains(q)) continue;
      out.add(HistoryLine(
        at: s.at,
        isRefund: false,
        number: s.number,
        saleNumber: s.number,
        line: l,
        payment: s.paymentLabel,
        cashier: s.cashierName,
      ));
    }
  }
  for (final r in data.refunds) {
    if (day != null && (r.at.isBefore(startOfDay(day)) || !r.at.isBefore(startOfDay(day).add(const Duration(days: 1))))) {
      continue;
    }
    for (final l in r.lines) {
      if (q.isNotEmpty && !l.name.toLowerCase().contains(q) && !'${r.number}'.contains(q) && !'${r.saleNumber}'.contains(q)) {
        continue;
      }
      out.add(HistoryLine(
        at: r.at,
        isRefund: true,
        number: r.number,
        saleNumber: r.saleNumber,
        line: l,
        payment: r.method,
        cashier: r.cashierName,
        authorisedBy: r.authorisedBy.isEmpty ? null : r.authorisedBy,
      ));
    }
  }
  out.sort((a, b) => b.at.compareTo(a.at));
  return out;
}

/// ------------------------------------------------------ inventory insight

List<Product> lowStockProducts(AppData data) {
  final list = data.products.where((p) => p.stock <= data.shop.lowStock).toList()
    ..sort((a, b) => a.stock.compareTo(b.stock));
  return list;
}

class StockDiscrepancy {
  final Product product;
  final double expected;
  final double found;
  const StockDiscrepancy(this.product, this.expected, this.found);

  double get difference => round2(found - expected);
}

/// Compares what the shelf should hold, according to the last report's
/// snapshot plus every sale and return since, with what it actually holds.
/// Anything left over is a change no sales record can explain.
List<StockDiscrepancy> unaccountedStock(AppData data, DateTime day) {
  final key = dateKey(day);
  final previous = data.snapshots.where((s) => s.date.compareTo(key) < 0).toList()
    ..sort((a, b) => b.at.compareTo(a.at));
  if (previous.isEmpty) return [];
  final snapshot = previous.first;
  final expected = Map<String, double>.from(snapshot.stock);

  for (final sale in data.sales) {
    if (sale.at.isBefore(snapshot.at)) continue;
    if (sale.voided) {
      if ((sale.voidedAt ?? sale.at).isAfter(snapshot.at)) {
        for (final l in sale.lines) {
          expected[l.productId] = (expected[l.productId] ?? 0) + l.qty;
        }
      }
    } else {
      for (final l in sale.lines) {
        expected[l.productId] = (expected[l.productId] ?? 0) - l.qty;
      }
    }
  }
  for (final refund in data.refunds) {
    if (refund.at.isBefore(snapshot.at)) continue;
    for (final l in refund.lines) {
      expected[l.productId] = (expected[l.productId] ?? 0) + l.qty;
    }
  }

  final list = <StockDiscrepancy>[];
  for (final p in data.products) {
    final found = p.stock;
    final want = expected[p.id] ?? 0;
    if ((found - want).abs() > 0.011) {
      list.add(StockDiscrepancy(p, round2(want), found));
    }
  }
  list.sort((a, b) => b.difference.abs().compareTo(a.difference.abs()));
  return list;
}

double inventoryValueAtCost(AppData data) =>
    round2(data.products.fold(0.0, (a, p) => a + max(0, p.stock) * p.cost));

double inventoryValueAtSell(AppData data) =>
    round2(data.products.fold(0.0, (a, p) => a + max(0, p.stock) * p.price));

/// --------------------------------------------------------------- the cart

class CartTotals {
  final double subtotal;
  final double tax;
  final double total;
  final double items;
  const CartTotals(this.subtotal, this.tax, this.total, this.items);
}
