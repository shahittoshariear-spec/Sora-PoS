import 'dart:io';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../analytics.dart';
import '../format.dart';
import '../models.dart';
import '../services/email.dart';
import '../services/native.dart';
import '../services/paths.dart';
import '../services/report_pdf.dart';
import '../store.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';

class ReportsScreen extends StatefulWidget {
  final Store store;
  const ReportsScreen({super.key, required this.store});

  @override
  State<ReportsScreen> createState() => ReportsScreenState();
}

class ReportsScreenState extends State<ReportsScreen> {
  DateTime _day = startOfDay(DateTime.now());
  bool _saving = false;
  bool _printing = false;
  bool _sending = false;

  Store get store => widget.store;
  bool get _isToday => dateKey(_day) == dateKey(DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isToday) store.captureSnapshot(_day);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: _day,
      helpText: 'Which day’s report?',
    );
    if (picked != null) setState(() => _day = startOfDay(picked));
  }

  Future<void> _savePdf({bool history = false}) async {
    setState(() => _saving = true);
    try {
      final bytes = history ? await salesHistoryPdf(store, _day) : await dayReportPdf(store, _day);
      final path = await NativeCore.saveDialog(
        title: history ? 'Save the sales history' : 'Save the day report',
        defaultName: '${history ? 'sales-history' : 'day-report'}-${dateKey(_day)}.pdf',
        filter: 'PDF|*.pdf',
      );
      if (path == null) return;
      await File(path).writeAsBytes(bytes, flush: true);
      if (_isToday) await store.captureSnapshot(_day);
      if (mounted) showToast(context, 'PDF saved');
    } catch (e) {
      if (mounted) showToast(context, 'Could not save the PDF. $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      final bytes = await dayReportPdf(store, _day);
      final dir = Directory(joinPath(store.rootDir.path, 'tmp'));
      await dir.create(recursive: true);
      final file = File(joinPath(dir.path, 'day-report-${dateKey(_day)}.pdf'));
      await file.writeAsBytes(bytes, flush: true);
      await NativeCore.printPdf(file.path, printer: store.data.settings.receiptPrinter);
      if (_isToday) await store.captureSnapshot(_day);
      if (mounted) showToast(context, 'Report sent to Windows printing');
    } catch (e) {
      if (mounted) showToast(context, 'Could not print the report. $e', error: true);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> sendEmail() async {
    if (_sending) return;
    if (store.data.settings.emailAddress.trim().isEmpty) {
      if (mounted) await _emailSetupHelp();
      return;
    }
    final password = await NativeCore.readSmtpPassword();
    if (password == null || password.isEmpty) {
      if (mounted) await _emailSetupHelp();
      return;
    }
    setState(() => _sending = true);
    final outcome = await EmailService.sendDayReport(store, _day);
    if (!mounted) return;
    setState(() => _sending = false);
    showToast(context, outcome.message, error: !outcome.ok);
  }

  Future<void> _emailSetupHelp() async {
    final p = context.palette;
    await showSoraDialog<void>(
      context,
      maxWidth: 470,
      builder: (context) => SoraDialog(
        title: 'Email is not set up yet',
        subtitle: 'Sora sends the report through the shop’s own Gmail account.',
        icon: Icons.mark_email_unread_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '1.  Open Setup → Email.\n'
              '2.  Add the shop’s Gmail address.\n'
              '3.  Make a Google App Password for Sora and save it there.',
              style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.7),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.accent.withValues(alpha: 0.16)),
              ),
              child: Text(
                'The App Password is kept in Windows Credential Manager, never in the shop’s data file.',
                style: TextStyle(fontSize: 10.5, color: p.faint, height: 1.4),
              ),
            ),
          ],
        ),
        actions: [
          GlassButton(label: 'Close', onPressed: () => Navigator.of(context).pop(), primary: true),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final totals = totalsForDay(store.data, _day);
    final start = startOfDay(_day);
    final end = start.add(const Duration(days: 1));
    final voids = store.data.sales
        .where((s) => s.voided && s.voidedAt != null && !s.voidedAt!.isBefore(start) && s.voidedAt!.isBefore(end))
        .toList()
      ..sort((a, b) => a.voidedAt!.compareTo(b.voidedAt!));
    final changes = store.data.audit
        .where((a) => !a.at.isBefore(start) && a.at.isBefore(end))
        .toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    final discrepancies = unaccountedStock(store.data, _day);
    final sellers = topSellers(store.data, start, end, limit: 5);
    final firstSale = totals.saleList.isEmpty ? null : totals.saleList.reduce((a, b) => a.at.isBefore(b.at) ? a : b).at;
    final lastSale = totals.saleList.isEmpty ? null : totals.saleList.reduce((a, b) => a.at.isAfter(b.at) ? a : b).at;
    final cashRefunded = round2(totals.refundList.fold(0.0, (a, r) => a + r.cash));
    final drawer = round2(totals.cash - cashRefunded);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GlassIconButton(
                icon: Icons.chevron_left_rounded,
                size: 38,
                tooltip: 'The day before',
                onPressed: () => setState(() => _day = _day.subtract(const Duration(days: 1))),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _pickDate,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GlassPanel(
                    blur: 16,
                    radius: 12,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_rounded, size: 14, color: p.accent),
                        const SizedBox(width: 8),
                        Text(dateLong(_day), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
                        if (_isToday) ...[
                          const SizedBox(width: 8),
                          StatusPill(label: 'TODAY', color: p.accent),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GlassIconButton(
                icon: Icons.chevron_right_rounded,
                size: 38,
                tooltip: 'The day after',
                onPressed: _isToday ? null : () => setState(() => _day = _day.add(const Duration(days: 1))),
              ),
              if (!_isToday) ...[
                const SizedBox(width: 8),
                GlassButton(label: 'Today', dense: true, onPressed: () => setState(() => _day = startOfDay(DateTime.now()))),
              ],
              const Spacer(),
              GlassButton(label: 'Save PDF', icon: Icons.picture_as_pdf_outlined, dense: true, loading: _saving, onPressed: _savePdf),
              const SizedBox(width: 7),
              GlassButton(label: 'Print', icon: Icons.print_rounded, dense: true, loading: _printing, onPressed: _print),
              const SizedBox(width: 7),
              GlassButton(label: 'Email', icon: Icons.mail_outline_rounded, primary: true, dense: true, loading: _sending, onPressed: sendEmail),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final item in [
                _Metric('SALES', totals.sales, p.accent, Icons.south_west_rounded),
                _Metric('REFUNDS', totals.refunds, p.danger, Icons.undo_rounded),
                _Metric('NET', totals.net, p.success, Icons.trending_up_rounded),
                _Metric('PROFIT', totals.profit, p.text, Icons.savings_outlined),
              ]) ...[
                Expanded(child: _MetricCard(metric: item, store: store)),
                const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 260,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GlassPanel(
                    blur: 20,
                    radius: 18,
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Row(
                        children: [
                          Text('The day', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
                          const Spacer(),
                          StatusPill(label: '${totals.transactions} sales', color: p.accent),
                        ],
                      ),
                      const SizedBox(height: 13),
                      _Info('First sale', firstSale == null ? '—' : timeShort(firstSale)),
                      _Info('Last sale', lastSale == null ? '—' : timeShort(lastSale)),
                      _Info('Cash taken', store.fmt(totals.cash)),
                      _Info('Card taken', store.fmt(totals.card)),
                      _Info('Cash refunded', store.fmt(cashRefunded)),
                      const Divider(height: 18),
                      Row(
                        children: [
                          Text('Expected in the drawer', style: TextStyle(fontSize: 12, color: p.muted)),
                          const Spacer(),
                          Text(
                            store.fmt(drawer),
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.accent, letterSpacing: -0.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GlassPanel(
                  blur: 20,
                  radius: 18,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('How it was paid', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
                      const SizedBox(height: 14),
                      _SplitBar(label: 'Cash', value: totals.cash, other: totals.card, color: p.accent, currency: store.currency),
                      const SizedBox(height: 14),
                      _SplitBar(label: 'Card', value: totals.card, other: totals.cash, color: p.accent2, currency: store.currency),
                      const Divider(height: 22),
                      _Info('Items sold', numText(totals.items)),
                      _Info('Inventory at cost', store.fmt(inventoryValueAtCost(store.data))),
                      _Info('Inventory at sell', store.fmt(inventoryValueAtSell(store.data))),
                      _Info('Low stock', '${lowStockProducts(store.data).length} items'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 240,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GlassPanel(
                    blur: 20,
                    radius: 18,
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Text('Top sellers', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
                      const SizedBox(height: 10),
                      if (sellers.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text('Nothing sold on this day.', style: TextStyle(fontSize: 11.5, color: p.faint)),
                        )
                      else
                        for (var i = 0; i < sellers.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: Row(
                              children: [
                                Text('${i + 1}', style: TextStyle(fontSize: 9.5, color: p.faint, fontWeight: FontWeight.w700)),
                                const SizedBox(width: 9),
                                Expanded(child: Text(sellers[i].name, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.text))),
                                Text('${numText(sellers[i].qty)} sold', style: TextStyle(fontSize: 10, color: p.faint)),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 78,
                                  child: Text(store.fmt(sellers[i].revenue), textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: p.muted)),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GlassPanel(
                  blur: 20,
                  radius: 18,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Voids', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
                          const SizedBox(width: 8),
                          if (voids.isNotEmpty) StatusPill(label: '${voids.length}', color: p.danger),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (voids.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text('No sale was voided on this day.', style: TextStyle(fontSize: 11.5, color: p.faint)),
                        )
                      else
                        for (final sale in voids)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Icon(Icons.block_rounded, size: 12, color: p.danger),
                                const SizedBox(width: 7),
                                Text('#${sale.number}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.danger)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${sale.voidedAt == null ? '' : timeShort(sale.voidedAt!)} · ${sale.voidedByName ?? ''}',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 10.5, color: p.faint),
                                  ),
                                ),
                                Text(store.fmt(sale.total), style: TextStyle(fontSize: 11, color: p.danger, decoration: TextDecoration.lineThrough)),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          ),
          const SizedBox(height: 10),
          GlassPanel(
            blur: 20,
            radius: 18,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 17, color: p.danger),
                    const SizedBox(width: 8),
                    Text('Changes the takings cannot account for', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.danger)),
                    const Spacer(),
                    Text('${changes.length} quietly written down', style: TextStyle(fontSize: 10.5, color: p.faint)),
                  ],
                ),
                const SizedBox(height: 11),
                if (changes.isEmpty)
                  Row(
                    children: [
                      Icon(Icons.check_circle_outline_rounded, size: 14, color: p.success),
                      const SizedBox(width: 7),
                      Text('Nothing was changed by hand.', style: TextStyle(fontSize: 11.5, color: p.muted)),
                    ],
                  )
                else
                  for (final entry in changes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 54,
                            child: Text(timeShort(entry.at), style: TextStyle(fontSize: 10.5, color: p.faint, fontFeatures: const [FontFeature.tabularFigures()])),
                          ),
                          Expanded(
                            child: Text(
                              '${entry.title} · ${entry.detail}',
                              style: TextStyle(fontSize: 11.5, color: p.danger, height: 1.35),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(entry.by ?? '', style: TextStyle(fontSize: 10.5, color: p.faint)),
                        ],
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GlassPanel(
            blur: 20,
            radius: 18,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 16, color: discrepancies.isEmpty ? p.success : p.danger),
                    const SizedBox(width: 8),
                    Text('Stock no sale explains', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text)),
                    const Spacer(),
                    Text('Counted against the last report', style: TextStyle(fontSize: 10.5, color: p.faint)),
                  ],
                ),
                const SizedBox(height: 11),
                if (discrepancies.isEmpty)
                  Row(
                    children: [
                      Icon(Icons.check_circle_outline_rounded, size: 14, color: p.success),
                      const SizedBox(width: 7),
                      Text('The shelf agrees with the last report and every sale since.', style: TextStyle(fontSize: 11.5, color: p.muted)),
                    ],
                  )
                else
                  Column(
                    children: [
                      Row(
                        children: [
                          const Expanded(flex: 4, child: SizedBox()),
                          SizedBox(width: 80, child: Text('EXPECTED', textAlign: TextAlign.right, style: overlineStyle(p, color: p.danger))),
                          SizedBox(width: 80, child: Text('FOUND', textAlign: TextAlign.right, style: overlineStyle(p, color: p.danger))),
                          SizedBox(width: 80, child: Text('DIFFERENCE', textAlign: TextAlign.right, style: overlineStyle(p, color: p.danger))),
                        ],
                      ),
                      const SizedBox(height: 5),
                      for (final d in discrepancies)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: Text(d.product.name, style: TextStyle(fontSize: 11.5, color: p.text)),
                              ),
                              SizedBox(width: 80, child: Text(numText(d.expected), textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: p.muted))),
                              SizedBox(width: 80, child: Text(numText(d.found), textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: p.muted))),
                              SizedBox(
                                width: 80,
                                child: Text(
                                  '${d.difference > 0 ? '+' : ''}${numText(d.difference)}',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.danger),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GlassPanel(
            blur: 16,
            radius: 18,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Row(
              children: [
                Icon(Icons.mail_outline_rounded, size: 17, color: p.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Two PDFs leave together',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.text),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        store.data.settings.emailAddress.isEmpty
                            ? 'Set the shop’s Gmail address and App Password in Setup → Email.'
                            : 'The day report and the day’s sales history go to ${store.data.settings.emailAddress}.${store.data.settings.autoEmail ? ' They also send themselves at ${store.data.settings.emailTime}.' : ''}',
                        style: TextStyle(fontSize: 10.5, color: p.faint, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                GlassButton(
                  label: 'Sales history PDF',
                  icon: Icons.table_rows_outlined,
                  dense: true,
                  onPressed: () => _savePdf(history: true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric {
  final String label;
  final double value;
  final Color color;
  final IconData icon;
  const _Metric(this.label, this.value, this.color, this.icon);
}

class _MetricCard extends StatelessWidget {
  final _Metric metric;
  final Store store;
  const _MetricCard({required this.metric, required this.store});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GlassPanel(
      blur: 18,
      radius: 17,
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
      child: Row(
        children: [
          Container(
            width: 31,
            height: 31,
            decoration: BoxDecoration(
              color: metric.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: metric.color.withValues(alpha: 0.18)),
            ),
            child: Icon(metric.icon, size: 15, color: metric.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(metric.label, style: overlineStyle(p)),
                const SizedBox(height: 4),
                Text(
                  store.fmt(metric.value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: p.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  final String label;
  final String value;
  const _Info(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: p.muted)),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 11.5, color: p.text, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _SplitBar extends StatelessWidget {
  final String label;
  final double value;
  final double other;
  final Color color;
  final String currency;
  const _SplitBar({required this.label, required this.value, required this.other, required this.color, required this.currency});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final total = value + other;
    final fraction = total == 0 ? 0.0 : (value / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 11.5, color: p.muted)),
            const Spacer(),
            Text(money(value, currency), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text)),
            const SizedBox(width: 7),
            Text('${(fraction * 100).toStringAsFixed(0)}%', style: TextStyle(fontSize: 9.5, color: p.faint)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(value: fraction, minHeight: 4, backgroundColor: p.raised, color: color),
        ),
      ],
    );
  }
}
