import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../store.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import '../widgets/sale_view.dart';

class LedgerScreen extends StatefulWidget {
  final Store store;
  const LedgerScreen({super.key, required this.store});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  final _search = TextEditingController();
  String _range = '30';
  DateTimeRange? _custom;
  int _visible = 500;

  Store get store => widget.store;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  DateTimeRange? get _bounds {
    final now = DateTime.now();
    final today = startOfDay(now);
    switch (_range) {
      case 'today':
        return DateTimeRange(start: today, end: today.add(const Duration(days: 1)));
      case '7':
        return DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today.add(const Duration(days: 1)));
      case '30':
        return DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today.add(const Duration(days: 1)));
      case 'month':
        return DateTimeRange(start: startOfMonth(now), end: startOfMonth(now).add(const Duration(days: 32)));
      case 'custom':
        if (_custom == null) return null;
        return DateTimeRange(start: startOfDay(_custom!.start), end: startOfDay(_custom!.end).add(const Duration(days: 1)));
      default:
        return null;
    }
  }

  bool _inRange(DateTime at) {
    final b = _bounds;
    if (b == null) return true;
    return !at.isBefore(b.start) && at.isBefore(b.end);
  }

  String get _rangeLabel {
    final b = _bounds;
    if (b == null) return 'All time';
    if (_range == 'custom') return '${dateMedium(b.start)} – ${dateMedium(b.end.subtract(const Duration(days: 1)))}';
    return switch (_range) {
      'today' => 'Today',
      '7' => 'Last 7 days',
      '30' => 'Last 30 days',
      'month' => monthYear(DateTime.now()),
      _ => 'All time',
    };
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final initial = _custom ?? DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: initial,
      helpText: 'Which days?',
      saveText: 'Use these',
      builder: (context, child) {
        final p = context.palette;
        return Theme(
          data: Theme.of(context).copyWith(
            datePickerTheme: DatePickerThemeData(
              backgroundColor: p.isLight ? const Color(0xFFF7F8FC) : const Color(0xFF11161F),
              headerBackgroundColor: Colors.transparent,
              headerForegroundColor: p.text,
              dayForegroundColor: WidgetStatePropertyAll(p.text),
              yearForegroundColor: WidgetStatePropertyAll(p.text),
              rangeSelectionBackgroundColor: p.accent.withValues(alpha: 0.18),
              rangePickerBackgroundColor: p.isLight ? const Color(0xFFF7F8FC) : const Color(0xFF11161F),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;
    setState(() {
      _custom = picked;
      _range = 'custom';
      _visible = 500;
    });
  }

  List<_Row> get _rows {
    final q = _search.text.trim().toLowerCase();
    final rows = <_Row>[];
    for (final s in store.data.sales) {
      if (!_inRange(s.at)) continue;
      if (q.isNotEmpty) {
        final matches = '${s.number}'.contains(q) ||
            s.cashierName.toLowerCase().contains(q) ||
            s.lines.any((l) => l.name.toLowerCase().contains(q));
        if (!matches) continue;
      }
      rows.add(_Row.sale(s));
    }
    for (final r in store.data.refunds) {
      if (!_inRange(r.at)) continue;
      if (q.isNotEmpty) {
        final matches = '${r.number}'.contains(q) ||
            '${r.saleNumber}'.contains(q) ||
            r.cashierName.toLowerCase().contains(q) ||
            r.lines.any((l) => l.name.toLowerCase().contains(q));
        if (!matches) continue;
      }
      rows.add(_Row.refund(r));
    }
    rows.sort((a, b) => b.at.compareTo(a.at));
    return rows;
  }

  Future<void> _view(_Row row) async {
    if (row.sale != null) {
      await showSaleSheet(context, store, row.sale!);
    } else if (row.refund != null) {
      await showRefundSheet(context, store, row.refund!);
    }
  }

  Future<void> _reprint(_Row row) async {
    if (row.sale != null) {
      await reprintSale(context, store, row.sale!);
    } else if (row.refund != null) {
      await reprintRefund(context, store, row.refund!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rows = _rows;
    final shown = rows.take(_visible).toList();
    double sales = 0, refunds = 0;
    for (final r in rows) {
      if (r.sale != null && !r.sale!.voided) sales += r.sale!.total;
      if (r.refund != null) refunds += r.refund!.total;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SoraField(
                controller: _search,
                hint: 'Receipt number, person, or item…',
                icon: Icons.search_rounded,
                dense: true,
                onChanged: (_) => setState(() => _visible = 500),
                suffix: _search.text.isEmpty
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: GestureDetector(
                          onTap: () {
                            _search.clear();
                            setState(() {});
                          },
                          child: Icon(Icons.close_rounded, size: 15, color: p.faint),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in const [
                    ['all', 'All time'],
                    ['today', 'Today'],
                    ['7', '7 days'],
                    ['30', '30 days'],
                    ['month', 'This month'],
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterPill(
                        label: entry[1],
                        selected: _range == entry[0],
                        onTap: () => setState(() {
                          _range = entry[0];
                          _visible = 500;
                        }),
                      ),
                    ),
                  FilterPill(
                    label: _range == 'custom' ? _rangeLabel : 'Pick days…',
                    icon: Icons.calendar_month_rounded,
                    selected: _range == 'custom',
                    onTap: _pickCustom,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text('${rows.length} ${plural(rows.length, 'record')}', style: TextStyle(fontSize: 11.5, color: p.muted, fontWeight: FontWeight.w500)),
            const SizedBox(width: 6),
            Text('· $_rangeLabel', style: TextStyle(fontSize: 11, color: p.faint)),
            const Spacer(),
            Text('Sales ${store.fmt(sales)}', style: TextStyle(fontSize: 11, color: p.muted)),
            const SizedBox(width: 12),
            Text('Refunds ${store.fmt(refunds)}', style: TextStyle(fontSize: 11, color: p.danger)),
            const SizedBox(width: 12),
            Text(
              'Net ${store.fmt(sales - refunds)}',
              style: TextStyle(fontSize: 11.5, color: p.accent, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: GlassPanel(
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
                      SizedBox(width: 104, child: _Head('When', p)),
                      SizedBox(width: 168, child: _Head('Receipt', p)),
                      SizedBox(width: 86, child: _Head('Kind', p)),
                      Expanded(flex: 3, child: _Head('What', p)),
                      SizedBox(width: 90, child: _Head('Payment', p)),
                      SizedBox(width: 130, child: _Head('Rung up by', p)),
                      SizedBox(width: 105, child: _Head('Total', p, align: TextAlign.right)),
                      const SizedBox(width: 118),
                    ],
                  ),
                ),
                Expanded(
                  child: shown.isEmpty
                      ? const EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'Nothing in this stretch',
                          message: 'Take a sale or pick a wider date range.',
                        )
                      : Scrollbar(
                          child: ListView.builder(
                            itemCount: shown.length,
                            itemBuilder: (context, index) {
                              final row = shown[index];
                              return _LedgerRow(
                                row: row,
                                store: store,
                                onView: () => _view(row),
                                onReprint: () => _reprint(row),
                              );
                            },
                          ),
                        ),
                ),
                if (shown.length < rows.length)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: p.hairline))),
                    child: TextButton(
                      onPressed: () => setState(() => _visible += 500),
                      child: Text('Show more  ·  ${rows.length - shown.length} still hidden'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Row {
  final Sale? sale;
  final RefundRecord? refund;
  _Row.sale(this.sale) : refund = null;
  _Row.refund(this.refund) : sale = null;
  DateTime get at => sale?.at ?? refund!.at;
}

class _Head extends StatelessWidget {
  final String text;
  final SoraPalette p;
  final TextAlign align;
  const _Head(this.text, this.p, {this.align = TextAlign.left});
  @override
  Widget build(BuildContext context) => Text(text, textAlign: align, style: overlineStyle(p));
}

class _LedgerRow extends StatefulWidget {
  final _Row row;
  final Store store;
  final VoidCallback onView;
  final VoidCallback onReprint;
  const _LedgerRow({required this.row, required this.store, required this.onView, required this.onReprint});

  @override
  State<_LedgerRow> createState() => _LedgerRowState();
}

class _LedgerRowState extends State<_LedgerRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sale = widget.row.sale;
    final refund = widget.row.refund;
    final isRefund = refund != null;
    final voided = sale?.voided == true;
    final total = sale?.total ?? refund!.total;
    final number = sale?.number ?? refund!.number;
    final cashier = sale?.cashierName ?? refund!.cashierName;
    final what = isRefund
        ? 'Refund of sale #${refund!.saleNumber} · ${numText(refund.itemCount)} ${plural(refund.itemCount, 'item')}'
        : '${numText(sale!.itemCount)} ${plural(sale.itemCount, 'item')} · ${sale.lines.take(2).map((e) => e.name).join(', ')}${sale.lines.length > 2 ? '…' : ''}';
    final kindColor = voided ? p.danger : isRefund ? p.warning : p.success;
    final kindLabel = voided ? 'VOID' : isRefund ? 'REFUND' : 'SALE';
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onView,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _hover ? p.accent.withValues(alpha: 0.055) : Colors.transparent,
            border: Border(bottom: BorderSide(color: p.hairline.withValues(alpha: 0.6))),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 104,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dateShort(widget.row.at), style: TextStyle(fontSize: 11.5, color: p.text, fontFeatures: const [FontFeature.tabularFigures()])),
                    Text(timeShort(widget.row.at), style: TextStyle(fontSize: 10, color: p.faint)),
                  ],
                ),
              ),
              SizedBox(
                width: 168,
                child: Row(
                  children: [
                    Text(
                      '#$number',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isRefund ? p.danger : p.text),
                    ),
                    if (isRefund) ...[
                      const SizedBox(width: 5),
                      Text('of #${refund.saleNumber}', style: TextStyle(fontSize: 9.5, color: p.faint)),
                    ],
                  ],
                ),
              ),
              SizedBox(
                width: 86,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: StatusPill(label: kindLabel, color: kindColor),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  what,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: voided ? p.faint : p.muted),
                ),
              ),
              SizedBox(
                width: 90,
                child: Text(
                  sale?.paymentLabel ?? refund!.method,
                  style: TextStyle(fontSize: 11.5, color: p.muted),
                ),
              ),
              SizedBox(
                width: 130,
                child: Text(cashier, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.muted)),
              ),
              SizedBox(
                width: 105,
                child: Text(
                  widget.store.fmt(total),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: voided ? p.faint : isRefund ? p.danger : p.text,
                    decoration: voided ? TextDecoration.lineThrough : null,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(
                width: 118,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AnimatedOpacity(
                      opacity: _hover ? 1 : 0.55,
                      duration: const Duration(milliseconds: 130),
                      child: TextButton(
                        onPressed: widget.onReprint,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 30),
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          foregroundColor: p.muted,
                        ),
                        child: const Text('Print', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onView,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                      ),
                      child: const Text('View', style: TextStyle(fontSize: 11)),
                    ),
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
