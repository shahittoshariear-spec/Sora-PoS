import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../analytics.dart';
import '../format.dart';
import '../models.dart';
import '../store.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import '../widgets/sale_view.dart';

class OverviewScreen extends StatefulWidget {
  final Store store;
  const OverviewScreen({super.key, required this.store});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  PeriodTab _tab = PeriodTab.day;
  bool _history = false;
  DateTime? _historyDay;
  final _historySearch = TextEditingController();
  final Set<String> _lowSelected = {};
  int _historyVisible = 800;

  Store get store => widget.store;

  @override
  void dispose() {
    _historySearch.dispose();
    super.dispose();
  }

  Future<void> _deleteLow(Iterable<String> ids) async {
    if (ids.isEmpty) return;
    final p = context.palette;
    final confirmed = await showSoraDialog<bool>(
      context,
      maxWidth: 440,
      builder: (context) => SoraDialog(
        title: 'Delete ${ids.length} ${plural(ids.length, 'product')}?',
        subtitle: 'Sales already recorded keep their own copy. The shelf loses only what is left.',
        icon: Icons.delete_outline_rounded,
        accent: p.danger,
        child: const SizedBox.shrink(),
        actions: [
          GlassButton(label: 'Keep them', onPressed: () => Navigator.of(context).pop(false)),
          GlassButton(label: 'Delete', danger: true, onPressed: () => Navigator.of(context).pop(true)),
        ],
      ),
    );
    if (confirmed != true) return;
    await store.deleteProducts(ids.toList());
    if (!mounted) return;
    setState(() => _lowSelected.clear());
    showToast(context, 'Deleted.');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final now = DateTime.now();
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 300,
                child: SoraSegmented<PeriodTab>(
                  values: PeriodTab.values,
                  selected: _tab,
                  label: (v) => v.label,
                  onChanged: (v) => setState(() {
                    _tab = v;
                    _historyVisible = 800;
                  }),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 210,
                child: SoraSegmented<bool>(
                  values: const [false, true],
                  selected: _history,
                  label: (v) => v ? 'History' : 'Figures',
                  dense: true,
                  onChanged: (v) => setState(() => _history = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_history) _historyView(now) else _figuresView(now),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- figures

  Widget _figuresView(DateTime now) {
    final p = context.palette;
    final start = periodStart(_tab, now);
    final end = periodEnd(_tab, now);
    final totals = totalsBetween(store.data, start, end);
    final prevStart = previousPeriodStart(_tab, start);
    final prev = totalsBetween(store.data, prevStart, start);
    final series = chartSeries(store.data, _tab, now);
    final sellers = topSellers(store.data, start, end, limit: 6);
    final low = lowStockProducts(store.data);
    final rows = periodHistory(store.data, _tab, now);
    final label = switch (_tab) {
      PeriodTab.day => 'yesterday',
      PeriodTab.week => 'last week',
      PeriodTab.month => 'last month',
      PeriodTab.year => 'last year',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'SALES',
                value: totals.sales,
                currency: store.currency,
                icon: Icons.south_west_rounded,
                change: _change(totals.sales, prev.sales),
                comparison: label,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: _StatCard(
                label: 'PROFIT',
                value: totals.profit,
                currency: store.currency,
                icon: Icons.trending_up_rounded,
                change: _change(totals.profit, prev.profit),
                comparison: label,
                accent: p.success,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: _StatCard(
                label: 'TRANSACTIONS',
                value: totals.transactions.toDouble(),
                currency: '',
                icon: Icons.receipt_long_rounded,
                change: _change(totals.transactions.toDouble(), prev.transactions.toDouble()),
                comparison: label,
                integer: true,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: _StatCard(
                label: 'ITEMS SOLD',
                value: totals.items,
                currency: '',
                icon: Icons.shopping_bag_outlined,
                change: _change(totals.items, prev.items),
                comparison: label,
                integer: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        SizedBox(
          height: 296,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: GlassPanel(
                  blur: 22,
                  radius: 20,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Takings and profit', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.text)),
                              const SizedBox(height: 3),
                              Text(_seriesLabel(), style: TextStyle(fontSize: 10.5, color: p.faint)),
                            ],
                          ),
                          const Spacer(),
                          _Legend(color: p.accent, label: 'Takings'),
                          const SizedBox(width: 12),
                          _Legend(color: p.accent2, label: 'Profit'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _LineChart(
                          key: ValueKey('chart-${_tab.name}'),
                          points: series,
                          currency: store.currency,
                          animate: !MediaQuery.disableAnimationsOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                flex: 3,
                child: GlassPanel(
                  blur: 22,
                  radius: 20,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('How they paid', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.text)),
                      const SizedBox(height: 3),
                      Text('Cash and card, net of refunds', style: TextStyle(fontSize: 10.5, color: p.faint)),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _PaymentSplit(
                          cash: math.max(0, totals.cash),
                          card: math.max(0, totals.card),
                          currency: store.currency,
                          transactions: totals.transactions,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 11),
        SizedBox(
          height: 300,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 2,
                child: GlassPanel(
                  blur: 22,
                  radius: 20,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Top sellers', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.text)),
                      const SizedBox(height: 3),
                      Text(_periodTitle(), style: TextStyle(fontSize: 10.5, color: p.faint)),
                      const SizedBox(height: 12),
                      Expanded(
                        child: sellers.isEmpty
                            ? Center(child: Text('Nothing sold in this stretch.', style: TextStyle(fontSize: 11.5, color: p.faint)))
                            : ListView.separated(
                                itemCount: sellers.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 9),
                                itemBuilder: (context, i) => _TopSellerRow(seller: sellers[i], rank: i + 1, maxQty: sellers.first.qty),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                flex: 3,
                child: GlassPanel(
                  blur: 22,
                  radius: 20,
                  padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Low stock', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.text)),
                          const SizedBox(width: 8),
                          if (low.isNotEmpty) StatusPill(label: '${low.length}', color: p.warning),
                          const Spacer(),
                          if (_lowSelected.isNotEmpty) ...[
                            Text('${_lowSelected.length} ticked', style: TextStyle(fontSize: 10, color: p.faint)),
                            const SizedBox(width: 6),
                            GlassButton(
                              label: 'Delete selected',
                              icon: Icons.delete_outline_rounded,
                              danger: true,
                              dense: true,
                              onPressed: () => _deleteLow(_lowSelected),
                            ),
                            const SizedBox(width: 4),
                          ],
                          TextButton(
                            onPressed: () async {
                              await showSoraDialog<void>(
                                context,
                                maxWidth: 650,
                                builder: (context) => _LowStockDialog(store: store),
                              );
                            },
                            child: const Text('Open', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: low.isEmpty
                            ? Center(
                                child: Text(
                                  'The shelf is comfortable. Nothing below ${numText(store.data.shop.lowStock)}.',
                                  style: TextStyle(fontSize: 11.5, color: p.faint),
                                ),
                              )
                            : ListView.builder(
                                itemCount: low.length,
                                itemBuilder: (context, i) {
                                  final product = low[i];
                                  return _LowRow(
                                    product: product,
                                    store: store,
                                    selected: _lowSelected.contains(product.id),
                                    onSelected: (v) => setState(() {
                                      if (v) {
                                        _lowSelected.add(product.id);
                                      } else {
                                        _lowSelected.remove(product.id);
                                      }
                                    }),
                                    onDelete: () => _deleteLow([product.id]),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 11),
        GlassPanel(
          blur: 22,
          radius: 20,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 15, 18, 10),
                child: Row(
                  children: [
                    Text('Sales history', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.text)),
                    const SizedBox(width: 8),
                    Text('cash and card, period by period', style: TextStyle(fontSize: 10.5, color: p.faint)),
                    const Spacer(),
                    Text(
                      'Shelf ${store.fmt(inventoryValueAtCost(store.data))} at cost · ${store.fmt(inventoryValueAtSell(store.data))} at sell',
                      style: TextStyle(fontSize: 10.5, color: p.muted),
                    ),
                  ],
                ),
              ),
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: p.hairline), bottom: BorderSide(color: p.hairline))),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: Text('PERIOD', style: overlineStyle(p))),
                    Expanded(flex: 2, child: Text('SALES', textAlign: TextAlign.right, style: overlineStyle(p))),
                    Expanded(flex: 2, child: Text('CASH', textAlign: TextAlign.right, style: overlineStyle(p))),
                    Expanded(flex: 2, child: Text('CARD', textAlign: TextAlign.right, style: overlineStyle(p))),
                    Expanded(flex: 2, child: Text('PROFIT', textAlign: TextAlign.right, style: overlineStyle(p))),
                    SizedBox(width: 80, child: Text('SALES', textAlign: TextAlign.right, style: overlineStyle(p))),
                  ],
                ),
              ),
              for (var i = 0; i < math.min(rows.length, 13); i++)
                Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: i == 0 ? p.accent.withValues(alpha: 0.05) : Colors.transparent,
                    border: Border(bottom: BorderSide(color: p.hairline.withValues(alpha: 0.5))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          rows[i].label,
                          style: TextStyle(fontSize: 11.5, color: i == 0 ? p.accent : p.text, fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400),
                        ),
                      ),
                      Expanded(flex: 2, child: Text(store.fmt(rows[i].totals.sales), textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, color: p.text))),
                      Expanded(flex: 2, child: Text(store.fmt(rows[i].totals.cash), textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, color: p.muted))),
                      Expanded(flex: 2, child: Text(store.fmt(rows[i].totals.card), textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, color: p.muted))),
                      Expanded(flex: 2, child: Text(store.fmt(rows[i].totals.profit), textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, color: rows[i].totals.profit < 0 ? p.danger : p.success))),
                      SizedBox(
                        width: 80,
                        child: Text('${rows[i].totals.transactions}', textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, color: p.muted)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _seriesLabel() => switch (_tab) {
        PeriodTab.day => 'the last 14 days',
        PeriodTab.week => 'the last 8 weeks',
        PeriodTab.month => 'the last 12 months',
        PeriodTab.year => 'the last 5 years',
      };

  String _periodTitle() => switch (_tab) {
        PeriodTab.day => 'Today',
        PeriodTab.week => 'This week',
        PeriodTab.month => 'This month',
        PeriodTab.year => 'This year',
      };

  double? _change(double current, double previous) {
    if (previous.abs() < 0.0001) return null;
    return ((current - previous) / previous.abs()) * 100;
  }

  // ---------------------------------------------------------------- history

  Widget _historyView(DateTime now) {
    final p = context.palette;
    final lines = lineHistory(store.data, day: _historyDay, query: _historySearch.text);
    final groups = <String, List<HistoryLine>>{};
    for (final line in lines) {
      groups.putIfAbsent(dateKey(line.at), () => []).add(line);
    }
    final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    final items = <_HistoryItem>[];
    for (final key in keys) {
      final day = DateTime.parse(key);
      final net = totalsForDay(store.data, day).net;
      items.add(_BandItem(day, groups[key]!.length, net));
      for (final line in groups[key]!) {
        items.add(_LineItem(line));
      }
    }
    final shown = items.take(_historyVisible).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SoraField(
                controller: _historySearch,
                hint: 'An item’s name, or a sale number — “dog food”, “1004”…',
                icon: Icons.search_rounded,
                dense: true,
                onChanged: (_) => setState(() => _historyVisible = 800),
                suffix: _historySearch.text.isEmpty
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: GestureDetector(
                          onTap: () {
                            _historySearch.clear();
                            setState(() {});
                          },
                          child: Icon(Icons.close_rounded, size: 15, color: p.faint),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 9),
            FilterPill(
              label: _historyDay == null ? 'All days' : dateMedium(_historyDay!),
              icon: Icons.calendar_today_rounded,
              selected: _historyDay != null,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(now.year + 1, 12, 31),
                  initialDate: _historyDay ?? now,
                  helpText: 'Which day?',
                );
                if (picked != null) {
                  setState(() {
                    _historyDay = picked;
                    _historyVisible = 800;
                  });
                }
              },
            ),
            if (_historyDay != null) ...[
              const SizedBox(width: 6),
              GlassIconButton(
                icon: Icons.close_rounded,
                size: 34,
                tooltip: 'Every day',
                onPressed: () => setState(() => _historyDay = null),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text('${lines.length} ${plural(lines.length, 'line')}', style: TextStyle(fontSize: 11.5, color: p.muted)),
            if (_historyDay != null) ...[
              const SizedBox(width: 6),
              Text('· ${dateLong(_historyDay!)}', style: TextStyle(fontSize: 11, color: p.faint)),
            ],
            const Spacer(),
            Text('Click a line to open its sale', style: TextStyle(fontSize: 10.5, color: p.faint)),
          ],
        ),
        const SizedBox(height: 10),
        GlassPanel(
          blur: 20,
          radius: 20,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.hairline))),
                child: Row(
                  children: [
                    SizedBox(width: 58, child: Text('TIME', style: overlineStyle(p))),
                    SizedBox(width: 92, child: Text('RECEIPT', style: overlineStyle(p))),
                    Expanded(flex: 4, child: Text('ITEM', style: overlineStyle(p))),
                    SizedBox(width: 50, child: Text('QTY', textAlign: TextAlign.right, style: overlineStyle(p))),
                    SizedBox(width: 76, child: Text('PRICE', textAlign: TextAlign.right, style: overlineStyle(p))),
                    SizedBox(width: 86, child: Text('LINE', textAlign: TextAlign.right, style: overlineStyle(p))),
                    SizedBox(width: 76, child: Text('PAID', style: overlineStyle(p))),
                    SizedBox(width: 160, child: Text('RUNG UP BY', style: overlineStyle(p))),
                  ],
                ),
              ),
              if (shown.isEmpty)
                const SizedBox(
                  height: 240,
                  child: EmptyState(
                    icon: Icons.history_rounded,
                    title: 'Nothing in this history',
                    message: 'No sale line matches. Try a shorter search, or a different day.',
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: shown.length,
                  itemBuilder: (context, index) {
                    final item = shown[index];
                    if (item is _BandItem) {
                      return Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: p.accent.withValues(alpha: 0.055),
                          border: Border(bottom: BorderSide(color: p.hairline)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_rounded, size: 12, color: p.accent),
                            const SizedBox(width: 7),
                            Text(dateLong(item.day), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.text)),
                            const SizedBox(width: 10),
                            Text('${item.count} ${plural(item.count, 'line')}', style: TextStyle(fontSize: 10, color: p.faint)),
                            const Spacer(),
                            Text('Day net  ', style: TextStyle(fontSize: 10, color: p.faint)),
                            Text(store.fmt(item.net), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.accent)),
                          ],
                        ),
                      );
                    }
                    final line = (item as _LineItem).line;
                    return _HistoryRow(line: line, store: store);
                  },
                ),
              if (shown.length < items.length)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: p.hairline))),
                  child: TextButton(
                    onPressed: () => setState(() => _historyVisible += 800),
                    child: Text('Show more  ·  ${items.length - shown.length} lines still hidden'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------- stat cards

class _StatCard extends StatelessWidget {
  final String label;
  final double value;
  final String currency;
  final IconData icon;
  final double? change;
  final String comparison;
  final Color? accent;
  final bool integer;

  const _StatCard({
    required this.label,
    required this.value,
    required this.currency,
    required this.icon,
    required this.change,
    required this.comparison,
    this.accent,
    this.integer = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tone = accent ?? p.accent;
    final up = (change ?? 0) >= 0;
    return GlassPanel(
      blur: 20,
      radius: 19,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 27,
                height: 27,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: tone.withValues(alpha: 0.2)),
                ),
                child: Icon(icon, size: 14, color: tone),
              ),
              const SizedBox(width: 9),
              Text(label, style: overlineStyle(p)),
            ],
          ),
          const SizedBox(height: 13),
          if (integer)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value),
              duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Text(
                math.max(0, v).round().toString(),
                style: TextStyle(fontSize: 27, fontWeight: FontWeight.w700, letterSpacing: -0.9, color: p.text, height: 1),
              ),
            )
          else
            AnimatedMoney(
              value: value,
              symbol: currency,
              style: TextStyle(fontSize: 27, fontWeight: FontWeight.w700, letterSpacing: -1, color: p.text, height: 1),
            ),
          const SizedBox(height: 9),
          Row(
            children: [
              if (change == null)
                Text('—', style: TextStyle(fontSize: 10, color: p.faint))
              else ...[
                Icon(
                  up ? Icons.north_east_rounded : Icons.south_east_rounded,
                  size: 11,
                  color: up ? p.success : p.danger,
                ),
                const SizedBox(width: 3),
                Text(
                  '${change!.abs().toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: up ? p.success : p.danger),
                ),
              ],
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'vs $comparison',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9.5, color: p.faint),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Container(width: 14, height: 2.5, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 9.5, color: p.faint)),
      ],
    );
  }
}

// ------------------------------------------------------------------- charts

class _LineChart extends StatefulWidget {
  final List<SeriesPoint> points;
  final String currency;
  final bool animate;
  const _LineChart({super.key, required this.points, required this.currency, required this.animate});

  @override
  State<_LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<_LineChart> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    if (widget.animate) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final empty = widget.points.every((e) => e.sales <= 0 && e.profit <= 0);
    return Stack(
      children: [
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _LineChartPainter(
              points: widget.points,
              palette: p,
              progress: _c.value,
              currency: widget.currency,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        if (empty)
          Center(
            child: Text(
              'No takings in this stretch yet.',
              style: TextStyle(fontSize: 11.5, color: p.faint),
            ),
          ),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<SeriesPoint> points;
  final SoraPalette palette;
  final double progress;
  final String currency;

  _LineChartPainter({required this.points, required this.palette, required this.progress, required this.currency});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const left = 6.0;
    const right = 6.0;
    const top = 8.0;
    const bottom = 26.0;
    final w = size.width - left - right;
    final h = size.height - top - bottom;
    if (w <= 0 || h <= 0) return;
    final maxValue = points.fold<double>(1, (a, p) => math.max(a, math.max(p.sales, p.profit)));
    final ceiling = _niceCeiling(maxValue);

    // grid
    final grid = Paint()
      ..color = palette.hairline
      ..strokeWidth = 0.7;
    for (var i = 0; i <= 3; i++) {
      final y = top + h * i / 3;
      canvas.drawLine(Offset(left, y), Offset(left + w, y), grid);
    }

    Offset pointAt(int i, double value) {
      final x = points.length == 1 ? left + w / 2 : left + w * i / (points.length - 1);
      final y = top + h - (value / ceiling) * h;
      return Offset(x, y);
    }

    Path pathFor(double Function(SeriesPoint) pick) {
      final path = Path();
      final count = points.length;
      final visible = (count * progress).ceil().clamp(1, count);
      for (var i = 0; i < visible; i++) {
        final pt = pointAt(i, pick(points[i]));
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          final prev = pointAt(i - 1, pick(points[i - 1]));
          final mid = Offset((prev.dx + pt.dx) / 2, (prev.dy + pt.dy) / 2);
          path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
          if (i == visible - 1) path.lineTo(pt.dx, pt.dy);
        }
      }
      return path;
    }

    final salesPath = pathFor((p) => p.sales);
    final profitPath = pathFor((p) => p.profit);
    final fill = Path.from(salesPath)
      ..lineTo(pointAt((points.length * progress).ceil().clamp(1, points.length) - 1, 0).dx, top + h)
      ..lineTo(left, top + h)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(left, top),
          Offset(left, top + h),
          [palette.accent.withValues(alpha: 0.20), palette.accent.withValues(alpha: 0)],
        ),
    );
    canvas.drawPath(
      salesPath,
      Paint()
        ..color = palette.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.1
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      profitPath,
      Paint()
        ..color = palette.accent2.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );

    // labels, thinned so they never collide
    final style = TextStyle(fontSize: 8.5, color: palette.faint, fontFeatures: const [FontFeature.tabularFigures()]);
    double widest = 0;
    for (final point in points) {
      final tp = TextPainter(text: TextSpan(text: point.label, style: style), textDirection: TextDirection.ltr)..layout();
      widest = math.max(widest, tp.width);
    }
    final step = math.max(1, ((widest + 12) / (w / math.max(1, points.length - 1))).ceil());
    for (var i = 0; i < points.length; i++) {
      if (i % step != 0 && i != points.length - 1) continue;
      final pt = pointAt(i, 0);
      final tp = TextPainter(text: TextSpan(text: points[i].label, style: style), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(pt.dx - tp.width / 2, top + h + 8));
    }

    // last point dot
    if (points.isNotEmpty) {
      final last = pointAt(points.length - 1, points.last.sales);
      canvas.drawCircle(last, 4.2, Paint()..color = palette.night.withValues(alpha: 0.85));
      canvas.drawCircle(last, 2.6, Paint()..color = palette.accent);
    }
  }

  double _niceCeiling(double value) {
    if (value <= 10) return 10;
    final magnitude = math.pow(10, (math.log(value) / math.ln10).floor()).toDouble();
    final normalized = value / magnitude;
    if (normalized <= 1) return magnitude;
    if (normalized <= 2) return 2 * magnitude;
    if (normalized <= 5) return 5 * magnitude;
    return 10 * magnitude;
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.progress != progress || old.palette.id != palette.id || old.points != points;
}

class _PaymentSplit extends StatelessWidget {
  final double cash;
  final double card;
  final String currency;
  final int transactions;
  const _PaymentSplit({required this.cash, required this.card, required this.currency, required this.transactions});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final total = cash + card;
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: total == 0 ? 0 : cash / total),
            duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 850),
            curve: Curves.easeOutCubic,
            builder: (context, fraction, _) => CustomPaint(
              painter: _RingPainter(fraction: fraction, palette: p),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('NET', style: overlineStyle(p)),
                    const SizedBox(height: 4),
                    Text(
                      money(total, currency),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: p.text),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          flex: 5,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PayRow(label: 'Cash', value: cash, total: total, color: p.accent, currency: currency),
              const SizedBox(height: 13),
              _PayRow(label: 'Card', value: card, total: total, color: p.accent2, currency: currency),
              const SizedBox(height: 16),
              Container(height: 1, color: p.hairline),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('Transactions', style: TextStyle(fontSize: 10, color: p.faint)),
                  const Spacer(),
                  Text(
                    '$transactions',
                    style: TextStyle(fontSize: 10.5, color: p.muted, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PayRow extends StatelessWidget {
  final String label;
  final double value;
  final double total;
  final Color color;
  final String currency;
  const _PayRow({required this.label, required this.value, required this.total, required this.color, required this.currency});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final percent = total == 0 ? 0 : (value / total * 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 7),
            Text(label, style: TextStyle(fontSize: 11.5, color: p.muted)),
            const Spacer(),
            Text(money(value, currency), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.text)),
            const SizedBox(width: 7),
            SizedBox(
              width: 34,
              child: Text('${percent.toStringAsFixed(0)}%', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: p.faint)),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : (value / total).clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: p.raised,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final SoraPalette palette;
  _RingPainter({required this.fraction, required this.palette});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 10;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round
      ..color = palette.raised;
    canvas.drawCircle(center, radius, base);
    final total = fraction.clamp(0.0, 1.0);
    if (total <= 0) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 11
          ..color = palette.hairline,
      );
      return;
    }
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * total,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11
        ..strokeCap = StrokeCap.round
        ..color = palette.accent,
    );
    if (total < 1) {
      canvas.drawArc(
        rect,
        -math.pi / 2 + 2 * math.pi * total,
        2 * math.pi * (1 - total),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 11
          ..strokeCap = StrokeCap.round
          ..color = palette.accent2.withValues(alpha: 0.65),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.fraction != fraction || old.palette.id != palette.id;
}

// ------------------------------------------------------------- top sellers

class _TopSellerRow extends StatelessWidget {
  final TopSeller seller;
  final int rank;
  final double maxQty;
  const _TopSellerRow({required this.seller, required this.rank, required this.maxQty});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text('$rank', style: TextStyle(fontSize: 10, color: p.faint, fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      seller.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: p.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${numText(seller.qty)}', style: TextStyle(fontSize: 10.5, color: p.muted, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: maxQty == 0 ? 0 : (seller.qty / maxQty).clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor: p.raised,
                  color: p.accent.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 72,
          child: Text(
            money(seller.revenue, 'R'),
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 10.5, color: p.muted),
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------- low stock

class _LowRow extends StatefulWidget {
  final Product product;
  final Store store;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final VoidCallback onDelete;
  const _LowRow({required this.product, required this.store, required this.selected, required this.onSelected, required this.onDelete});

  @override
  State<_LowRow> createState() => _LowRowState();
}

class _LowRowState extends State<_LowRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 38,
        padding: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.hairline.withValues(alpha: 0.55))),
          color: _hover ? p.accent.withValues(alpha: 0.06) : Colors.transparent,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Checkbox(value: widget.selected, onChanged: (v) => widget.onSelected(v == true)),
            ),
            Expanded(
              child: Text(
                widget.product.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: p.text),
              ),
            ),
            Text(
              widget.product.sku,
              style: TextStyle(fontSize: 9.5, color: p.faint, fontFamily: 'JetBrains Mono'),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: p.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: p.warning.withValues(alpha: 0.24)),
              ),
              child: Text('${numText(widget.product.stock)}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: p.warning)),
            ),
            const SizedBox(width: 6),
            TextButton(
              onPressed: widget.onDelete,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 28),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                foregroundColor: p.danger,
              ),
              child: const Text('Delete', style: TextStyle(fontSize: 10)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LowStockDialog extends StatefulWidget {
  final Store store;
  const _LowStockDialog({required this.store});
  @override
  State<_LowStockDialog> createState() => _LowStockDialogState();
}

class _LowStockDialogState extends State<_LowStockDialog> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final low = lowStockProducts(widget.store.data);
    return SoraDialog(
      title: 'Low stock',
      subtitle: 'Everything at or below ${numText(widget.store.data.shop.lowStock)}.',
      icon: Icons.warning_amber_rounded,
      width: 650,
      child: Column(
        children: [
          if (low.isEmpty)
            const EmptyState(icon: Icons.check_circle_outline_rounded, title: 'The shelf is comfortable')
          else ...[
            for (final product in low)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: p.raised,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.hairline),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _selected.contains(product.id),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(product.id);
                          } else {
                            _selected.remove(product.id);
                          }
                        }),
                      ),
                      Expanded(child: Text(product.name, style: TextStyle(fontSize: 12.5, color: p.text))),
                      Text(product.sku, style: TextStyle(fontSize: 10, color: p.faint, fontFamily: 'JetBrains Mono')),
                      const SizedBox(width: 14),
                      Text('${numText(product.stock)} left', style: TextStyle(fontSize: 11, color: p.warning, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      IconButton(
                        onPressed: () async {
                          await widget.store.deleteProduct(product.id);
                          if (mounted) setState(() {});
                        },
                        icon: Icon(Icons.delete_outline_rounded, size: 16, color: p.danger),
                        splashRadius: 18,
                      ),
                    ],
                  ),
                ),
              ),
            if (_selected.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: GlassButton(
                  label: 'Delete ${_selected.length} selected',
                  icon: Icons.delete_outline_rounded,
                  danger: true,
                  onPressed: () async {
                    await widget.store.deleteProducts(_selected.toList());
                    if (mounted) setState(() => _selected.clear());
                  },
                ),
              ),
          ],
        ],
      ),
      actions: [
        GlassButton(label: 'Close', onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}

// ----------------------------------------------------------------- history

abstract class _HistoryItem {}

class _BandItem extends _HistoryItem {
  final DateTime day;
  final int count;
  final double net;
  _BandItem(this.day, this.count, this.net);
}

class _LineItem extends _HistoryItem {
  final HistoryLine line;
  _LineItem(this.line);
}

class _HistoryRow extends StatefulWidget {
  final HistoryLine line;
  final Store store;
  const _HistoryRow({required this.line, required this.store});
  @override
  State<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<_HistoryRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final line = widget.line;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          if (line.isRefund) {
            final refund = widget.store.data.refunds.where((r) => r.number == line.number).toList();
            if (refund.isNotEmpty) showRefundSheet(context, widget.store, refund.first);
          } else {
            final sale = widget.store.saleByNumber(line.number);
            if (sale != null) showSaleSheet(context, widget.store, sale);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _hover ? p.accent.withValues(alpha: 0.05) : Colors.transparent,
            border: Border(bottom: BorderSide(color: p.hairline.withValues(alpha: 0.45))),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 58,
                child: Text(timeShort(line.at), style: TextStyle(fontSize: 10.5, color: p.faint, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              SizedBox(
                width: 92,
                child: Text(
                  line.isRefund ? '#${line.number}R' : '#${line.number}',
                  style: TextStyle(fontSize: 10.5, color: line.isRefund ? p.danger : p.muted, fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    if (line.isRefund) ...[
                      Icon(Icons.undo_rounded, size: 11, color: p.danger),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        line.line.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: line.isRefund ? p.danger : p.text),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 50,
                child: Text(numText(line.line.qty), textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: p.muted)),
              ),
              SizedBox(
                width: 76,
                child: Text(widget.store.fmt(line.line.unitPrice), textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: p.muted)),
              ),
              SizedBox(
                width: 86,
                child: Text(
                  '${line.isRefund ? '-' : ''}${widget.store.fmt(line.line.total)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: line.isRefund ? p.danger : p.text),
                ),
              ),
              SizedBox(
                width: 76,
                child: Text(line.isRefund ? 'Refund' : line.payment, style: TextStyle(fontSize: 10.5, color: p.muted)),
              ),
              SizedBox(
                width: 160,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line.cashier, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: p.muted)),
                    if (line.authorisedBy != null)
                      Text('ok: ${line.authorisedBy}', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 8.5, color: p.faint)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
