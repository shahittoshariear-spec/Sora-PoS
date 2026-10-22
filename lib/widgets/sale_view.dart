import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../models.dart';
import '../services/native.dart';
import '../services/paths.dart';
import '../services/receipts.dart';
import '../store.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import 'authorize.dart';

Future<void> showSaleSheet(BuildContext context, Store store, Sale sale) async {
  await showSoraDialog<void>(
    context,
    maxWidth: 900,
    builder: (context) => _SaleSheet(store: store, sale: sale),
  );
}

Future<void> showRefundSheet(
  BuildContext context,
  Store store,
  RefundRecord refund,
) async {
  final sale = store.saleByNumber(refund.saleNumber);
  await showSoraDialog<void>(
    context,
    maxWidth: 900,
    builder: (context) =>
        _RefundSheet(store: store, refund: refund, sale: sale),
  );
}

Future<void> showReceiptAfterSale(
  BuildContext context,
  Store store,
  Sale sale,
) async {
  await showSoraDialog<void>(
    context,
    maxWidth: 940,
    builder: (context) => _SaleCompleteSheet(store: store, sale: sale),
  );
}

Future<void> reprintSale(BuildContext context, Store store, Sale sale) async {
  final printer = store.data.settings.receiptPrinter;
  final text = saleReceiptText(store, sale, reprint: true);
  if (printer.isNotEmpty) {
    try {
      await NativeCore.printRaw(
        printer,
        escPosBytes(text, cut: store.data.settings.cutPaper),
      );
      if (context.mounted) showToast(context, 'Sent to $printer');
      return;
    } catch (e) {
      if (context.mounted) {
        showToast(
          context,
          'The printer did not take the receipt. $e',
          error: true,
        );
      }
    }
  }
  if (context.mounted)
    await showPrintOptions(context, store, text, 'receipt-${sale.number}.pdf');
}

Future<void> reprintRefund(
  BuildContext context,
  Store store,
  RefundRecord refund,
) async {
  final printer = store.data.settings.receiptPrinter;
  final text = refundReceiptText(store, refund, reprint: true);
  if (printer.isNotEmpty) {
    try {
      await NativeCore.printRaw(
        printer,
        escPosBytes(text, cut: store.data.settings.cutPaper),
      );
      if (context.mounted) showToast(context, 'Sent to $printer');
      return;
    } catch (e) {
      if (context.mounted) {
        showToast(
          context,
          'The printer did not take the receipt. $e',
          error: true,
        );
      }
    }
  }
  if (context.mounted)
    await showPrintOptions(context, store, text, 'refund-${refund.number}.pdf');
}

Future<void> showPrintOptions(
  BuildContext context,
  Store store,
  String text,
  String fileName,
) async {
  await showSoraDialog<void>(
    context,
    maxWidth: 470,
    builder: (context) =>
        _PrintOptionsDialog(store: store, text: text, fileName: fileName),
  );
}

Future<void> saveReceiptPdf(
  BuildContext context,
  Store store,
  String text,
  String fileName,
) async {
  try {
    final path = await NativeCore.saveDialog(
      title: 'Save the receipt',
      defaultName: fileName,
      filter: 'PDF|*.pdf',
    );
    if (path == null) return;
    final bytes = await receiptPdfBytes(text);
    await File(path).writeAsBytes(bytes, flush: true);
    if (context.mounted) showToast(context, 'Receipt saved');
  } catch (e) {
    if (context.mounted)
      showToast(context, 'Could not save the PDF. $e', error: true);
  }
}

Future<void> refundFlow(BuildContext context, Store store, Sale sale) async {
  await showSoraDialog<void>(
    context,
    maxWidth: 660,
    builder: (context) => _RefundFlow(store: store, sale: sale),
  );
}

Future<void> voidFlow(BuildContext context, Store store, Sale sale) async {
  final p = context.palette;
  final approved = store.isManagerOrOwner
      ? store.current
      : await askApproval(
          context,
          store,
          reason: 'A void needs an owner or manager to allow it.',
        );
  if (approved == null || !context.mounted) return;
  final confirmed = await showSoraDialog<bool>(
    context,
    maxWidth: 470,
    builder: (context) => SoraDialog(
      title: 'Void sale #${sale.number}?',
      subtitle: 'It stays in the Ledger marked VOID, stops counting towards every figure, and its stock goes back on the shelf.',
      icon: Icons.block_rounded,
      accent: p.danger,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: p.danger.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: p.danger),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'This cannot be undone. A refund is the gentler choice if money already changed hands.',
                style: TextStyle(fontSize: 11.5, color: p.muted, height: 1.4),
              ),
            ),
          ],
        ),
      ),
      actions: [
        GlassButton(
          label: 'Keep the sale',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        GlassButton(
          label: 'Void it',
          icon: Icons.block_rounded,
          danger: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await store.voidSale(sale, approvedBy: approved);
    if (context.mounted) showToast(context, 'Sale #${sale.number} is void');
  } catch (e) {
    if (context.mounted) showToast(context, e.toString(), error: true);
  }
}

// --------------------------------------------------------------- sale sheet

class _SaleSheet extends StatelessWidget {
  final Store store;
  final Sale sale;
  const _SaleSheet({required this.store, required this.sale});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final refunds = store.data.refunds
        .where((r) => r.saleNumber == sale.number)
        .toList();
    final remaining = store.availableForRefund(sale);
    final canRefund = !sale.voided && remaining.isNotEmpty;
    return SoraDialog(
      title: 'Sale #${sale.number}',
      subtitle:
          '${dateLong(sale.at)} · ${timeShort(sale.at)} · rung up by ${sale.cashierName}',
      icon: sale.voided ? Icons.block_rounded : Icons.receipt_long_rounded,
      accent: sale.voided ? p.danger : null,
      width: 900,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReceiptPaper(
                text: saleReceiptText(store, sale, reprint: true),
                width: 336,
              ),
              const SizedBox(width: 28),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (sale.voided)
                          StatusPill(
                            label: 'VOID',
                            color: p.danger,
                            icon: Icons.block_rounded,
                          )
                        else
                          StatusPill(
                            label: 'PAID',
                            color: p.success,
                            icon: Icons.check_rounded,
                          ),
                        const SizedBox(width: 8),
                        StatusPill(label: sale.paymentLabel, color: p.accent),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _MetaRow(
                      label: 'Total',
                      value: store.fmt(sale.total),
                      big: true,
                    ),
                    _MetaRow(
                      label: 'Subtotal',
                      value: store.fmt(sale.subtotal),
                    ),
                    _MetaRow(label: 'Tax', value: store.fmt(sale.tax)),
                    _MetaRow(label: 'Items', value: numText(sale.itemCount)),
                    if (sale.card > 0)
                      _MetaRow(label: 'Card', value: store.fmt(sale.card)),
                    if (sale.cash > 0)
                      _MetaRow(label: 'Cash', value: store.fmt(sale.cash)),
                    if (sale.change > 0)
                      _MetaRow(
                        label: 'Change given',
                        value: store.fmt(sale.change),
                      ),
                    if (sale.voided) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Voided ${sale.voidedAt == null ? '' : timeShort(sale.voidedAt!)} by ${sale.voidedByName ?? 'a manager'}.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: p.danger,
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (refunds.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      SectionLabel('Refunds on this sale'),
                      const SizedBox(height: 9),
                      for (final r in refunds)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: GlassPanel(
                            blur: 0,
                            radius: 12,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.undo_rounded,
                                  size: 14,
                                  color: p.danger,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Refund #${r.number} · ${store.fmt(r.total)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: p.text,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      showRefundSheet(context, store, r),
                                  child: const Text('View'),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 9,
                      runSpacing: 9,
                      children: [
                        GlassButton(
                          label: 'Print',
                          icon: Icons.print_rounded,
                          onPressed: () => reprintSale(context, store, sale),
                        ),
                        if (canRefund)
                          GlassButton(
                            label: 'Refund items',
                            icon: Icons.undo_rounded,
                            primary: true,
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await Future<void>.delayed(
                                const Duration(milliseconds: 120),
                              );
                              if (context.mounted)
                                await refundFlow(context, store, sale);
                            },
                          ),
                        if (!sale.voided)
                          GlassButton(
                            label: 'Void',
                            icon: Icons.block_rounded,
                            danger: true,
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await Future<void>.delayed(
                                const Duration(milliseconds: 120),
                              );
                              if (context.mounted)
                                await voidFlow(context, store, sale);
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        GlassButton(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _RefundSheet extends StatelessWidget {
  final Store store;
  final RefundRecord refund;
  final Sale? sale;
  const _RefundSheet({required this.store, required this.refund, this.sale});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SoraDialog(
      title: 'Refund #${refund.number}',
      subtitle:
          'Of sale #${refund.saleNumber} · ${dateLong(refund.at)} · ${timeShort(refund.at)}',
      icon: Icons.undo_rounded,
      accent: p.danger,
      width: 900,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReceiptPaper(
            text: refundReceiptText(store, refund, reprint: true),
            width: 336,
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusPill(
                  label: 'REFUNDED',
                  color: p.danger,
                  icon: Icons.undo_rounded,
                ),
                const SizedBox(height: 20),
                _MetaRow(
                  label: 'Returned',
                  value: store.fmt(refund.total),
                  big: true,
                ),
                _MetaRow(label: 'Items', value: numText(refund.itemCount)),
                _MetaRow(label: 'Method', value: refund.method),
                _MetaRow(label: 'Handed back by', value: refund.cashierName),
                if (refund.authorisedBy.isNotEmpty)
                  _MetaRow(label: 'Allowed by', value: refund.authorisedBy),
                if ((refund.reason ?? '').isNotEmpty) ...[
                  const SizedBox(height: 14),
                  SectionLabel('Reason'),
                  const SizedBox(height: 6),
                  Text(
                    refund.reason!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: p.muted,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Wrap(
                  spacing: 9,
                  children: [
                    GlassButton(
                      label: 'Print refund',
                      icon: Icons.print_rounded,
                      onPressed: () => reprintRefund(context, store, refund),
                    ),
                    if (sale != null)
                      GlassButton(
                        label: 'Open sale',
                        icon: Icons.receipt_long_rounded,
                        onPressed: () {
                          Navigator.of(context).pop();
                          showSaleSheet(context, store, sale!);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        GlassButton(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  final bool big;
  const _MetaRow({required this.label, required this.value, this.big = false});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: big ? 9 : 4.5),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: big ? 12.5 : 12, color: p.muted),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: big ? 24 : 12.5,
              fontWeight: big ? FontWeight.w700 : FontWeight.w500,
              color: big ? p.text : p.text,
              letterSpacing: big ? -0.5 : 0,
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- sale complete

class _SaleCompleteSheet extends StatelessWidget {
  final Store store;
  final Sale sale;
  const _SaleCompleteSheet({required this.store, required this.sale});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = saleReceiptText(store, sale);
    return SoraDialog(
      title: 'Sale complete',
      subtitle:
          'Receipt #${sale.number} · ${timeShort(sale.at)} · ${sale.paymentLabel}',
      icon: Icons.check_rounded,
      accent: p.success,
      width: 900,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReceiptPaper(text: text, width: 340, celebrate: true),
          const SizedBox(width: 30),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusPill(
                      label: 'PAID',
                      color: p.success,
                      icon: Icons.check_rounded,
                    ),
                    const SizedBox(width: 8),
                    StatusPill(label: sale.paymentLabel, color: p.accent),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  store.fmt(sale.total),
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.4,
                    color: p.text,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${numText(sale.itemCount)} ${plural(sale.itemCount, 'item')} · ${store.data.shop.name}',
                  style: TextStyle(fontSize: 12, color: p.muted),
                ),
                if (sale.change > 0) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: p.accent.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.payments_outlined,
                          size: 17,
                          color: p.accent,
                        ),
                        const SizedBox(width: 9),
                        Text(
                          'Change',
                          style: TextStyle(fontSize: 12, color: p.muted),
                        ),
                        const Spacer(),
                        Text(
                          store.fmt(sale.change),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: p.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: [
                    GlassButton(
                      label: 'Print receipt',
                      icon: Icons.print_rounded,
                      primary: true,
                      onPressed: () => reprintSale(context, store, sale),
                    ),
                    GlassButton(
                      label: 'Save PDF',
                      icon: Icons.picture_as_pdf_outlined,
                      onPressed: () => saveReceiptPdf(
                        context,
                        store,
                        text,
                        'receipt-${sale.number}.pdf',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  store.data.settings.receiptPrinter.isEmpty
                      ? 'No receipt printer is set, so the receipt stays on screen. Choose one in Setup → Receipt.'
                      : 'The receipt was sent to ${store.data.settings.receiptPrinter}.',
                  style: TextStyle(fontSize: 10.5, color: p.faint, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        GlassButton(
          label: 'New sale',
          icon: Icons.add_rounded,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ receipt

class ReceiptPaper extends StatefulWidget {
  final String text;
  final double width;
  final double maxHeight;
  final bool celebrate;

  const ReceiptPaper({
    super.key,
    required this.text,
    this.width = 340,
    this.maxHeight = 540,
    this.celebrate = false,
  });

  @override
  State<ReceiptPaper> createState() => _ReceiptPaperState();
}

class _ReceiptPaperState extends State<ReceiptPaper> {
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Half-point steps: the live receipt reflows while the pane is dragged, and
    // every distinct font size creates a new text layout. Quantising keeps the
    // shaping cache bounded without a visible difference.
    final fontSize = ((((widget.width - 30) / 36) * 2).round() / 2).clamp(
      7.0,
      16.0,
    );
    final paper = Container(
      width: widget.width,
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      padding: const EdgeInsets.fromLTRB(17, 20, 17, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFAF6),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: p.accent.withValues(alpha: widget.celebrate ? 0.12 : 0.0),
            blurRadius: 40,
            spreadRadius: 2,
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Text(
          widget.text,
          style: TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: fontSize,
            height: 1.5,
            color: const Color(0xFF20242B),
            letterSpacing: 0,
          ),
        ),
      ),
    );

    final stack = Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.celebrate)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) => Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: p.accent.withValues(alpha: 0.35 * (1 - t)),
                        blurRadius: 30,
                        spreadRadius: 4 * (1 - t),
                      ),
                    ],
                  ),
                  child: child,
                ),
                child: paper,
              )
            else
              paper,
            CustomPaint(
              size: Size(widget.width, 9),
              painter: _TornEdgePainter(const Color(0xFFFBFAF6)),
            ),
          ],
        ),
      ],
    );
    return SizedBox(width: widget.width + 12, child: stack);
  }
}

class _TornEdgePainter extends CustomPainter {
  final Color paper;
  _TornEdgePainter(this.paper);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = paper;
    final path = Path()..moveTo(0, 0);
    final teeth = (size.width / 9).floor();
    for (var i = 0; i < teeth; i++) {
      final x = i * 9.0;
      path
        ..lineTo(x + 4.5, size.height * (i.isEven ? 0.85 : 0.35))
        ..lineTo(x + 9, 0);
    }
    path
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TornEdgePainter old) => old.paper != paper;
}

// -------------------------------------------------------------- refund flow

class _RefundFlow extends StatefulWidget {
  final Store store;
  final Sale sale;
  const _RefundFlow({required this.store, required this.sale});

  @override
  State<_RefundFlow> createState() => _RefundFlowState();
}

class _RefundFlowState extends State<_RefundFlow> {
  late final Map<String, double> _available;
  final Map<String, double> _quantities = {};
  final _reason = TextEditingController();
  String _method = 'Same as sale';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _available = widget.store.availableForRefund(widget.sale);
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _setQty(String productId, double qty) {
    setState(() {
      final max = _available[productId] ?? 0;
      final next = qty.clamp(0.0, max);
      if (next <= 0) {
        _quantities.remove(productId);
      } else {
        _quantities[productId] = next;
      }
    });
  }

  Future<void> _submit() async {
    if (_quantities.isEmpty) {
      setState(() => _error = 'Choose at least one item to refund.');
      return;
    }
    setState(() => _error = null);
    final approved = widget.store.isManagerOrOwner
        ? widget.store.current
        : await askApproval(
            context,
            widget.store,
            reason: 'A refund needs an owner or manager to allow it.',
          );
    if (approved == null || !mounted) return;
    final totals = widget.store.refundTotals(widget.sale, _quantities);
    double cash = 0;
    double card = 0;
    String method = _method;
    if (_method == 'Cash') {
      cash = totals.total;
    } else if (_method == 'Card') {
      card = totals.total;
    } else {
      final ratio = widget.sale.total == 0
          ? 1.0
          : (widget.sale.cash / widget.sale.total).clamp(0.0, 1.0);
      cash = round2(totals.total * ratio);
      card = round2(totals.total - cash);
      method = cash > 0 && card > 0 ? 'Split' : (card > 0 ? 'Card' : 'Cash');
    }
    setState(() => _busy = true);
    try {
      final refund = await widget.store.refundSale(
        sale: widget.sale,
        quantities: _quantities,
        method: method,
        cash: cash,
        card: card,
        approvedBy: approved,
        reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (context.mounted) await showRefundSheet(context, widget.store, refund);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final totals = widget.store.refundTotals(widget.sale, _quantities);
    return SoraDialog(
      title: 'Refund items',
      subtitle: 'Sale #${widget.sale.number} · ${dateMedium(widget.sale.at)}',
      icon: Icons.undo_rounded,
      accent: p.danger,
      width: 660,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final line in widget.sale.lines)
            if ((_available[line.productId] ?? 0) > 0)
              _RefundLine(
                line: line,
                max: _available[line.productId]!,
                value: _quantities[line.productId] ?? 0,
                onChanged: (v) => _setQty(line.productId, v),
                currency: widget.store.currency,
              ),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _quantities
                      ..clear()
                      ..addAll(_available);
                  });
                },
                child: const Text('Refund everything'),
              ),
              const Spacer(),
              if (_quantities.isNotEmpty)
                TextButton(
                  onPressed: () => setState(_quantities.clear),
                  child: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SectionLabel('How the money goes back'),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final method in ['Same as sale', 'Cash', 'Card']) ...[
                FilterPill(
                  label: method,
                  selected: _method == method,
                  onTap: () => setState(() => _method = method),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 16),
          SoraField(
            controller: _reason,
            label: 'Reason (optional)',
            hint: 'What happened?',
            dense: true,
            maxLines: 2,
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.danger.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.danger.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Text(
                  'Returning',
                  style: TextStyle(fontSize: 12.5, color: p.muted),
                ),
                const Spacer(),
                Text(
                  widget.store.fmt(totals.total),
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    color: p.danger,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(fontSize: 12, color: p.danger)),
          ],
        ],
      ),
      actions: [
        GlassButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        GlassButton(
          label: 'Refund ${widget.store.fmt(totals.total)}',
          icon: Icons.undo_rounded,
          danger: true,
          loading: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _RefundLine extends StatelessWidget {
  final SaleLine line;
  final double max;
  final double value;
  final ValueChanged<double> onChanged;
  final String currency;

  const _RefundLine({
    required this.line,
    required this.max,
    required this.value,
    required this.onChanged,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: p.raised,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: p.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: p.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$currency${moneyPlain(line.unitPrice)} each · $max left on the sale',
                    style: TextStyle(fontSize: 10.5, color: p.faint),
                  ),
                ],
              ),
            ),
            _StepButton(
              icon: Icons.remove_rounded,
              onTap: () => onChanged(value - 1),
            ),
            SizedBox(
              width: 42,
              child: Text(
                numText(value),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: p.text,
                ),
              ),
            ),
            _StepButton(
              icon: Icons.add_rounded,
              onTap: () => onChanged(value + 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 27,
        height: 27,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: p.raised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.hairline),
        ),
        child: Icon(icon, size: 14, color: p.muted),
      ),
    );
  }
}

// ------------------------------------------------------------- print options

class _PrintOptionsDialog extends StatefulWidget {
  final Store store;
  final String text;
  final String fileName;
  const _PrintOptionsDialog({
    required this.store,
    required this.text,
    required this.fileName,
  });

  @override
  State<_PrintOptionsDialog> createState() => _PrintOptionsDialogState();
}

class _PrintOptionsDialogState extends State<_PrintOptionsDialog> {
  List<String> _printers = [];
  String? _selected;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    NativeCore.printers().then((list) {
      if (!mounted) return;
      setState(() {
        _printers = list;
        final live = widget.store.data.settings.receiptPrinter;
        _selected = list.contains(live)
            ? live
            : (list.isNotEmpty ? list.first : null);
        _loading = false;
      });
    });
  }

  Future<void> _print() async {
    if (_selected == null) return;
    setState(() => _busy = true);
    try {
      await NativeCore.printRaw(
        _selected!,
        escPosBytes(widget.text, cut: widget.store.data.settings.cutPaper),
      );
      if (mounted) {
        Navigator.of(context).pop();
        showToast(context, 'Sent to $_selected');
      }
    } catch (e) {
      setState(() {
        _busy = false;
        _selected = _selected;
      });
      if (mounted)
        showToast(context, 'The printer did not take it. $e', error: true);
    }
  }

  Future<void> _systemPrint() async {
    setState(() => _busy = true);
    try {
      final tmp = Directory(joinPath(widget.store.rootDir.path, 'tmp'));
      await tmp.create(recursive: true);
      final file = File(joinPath(tmp.path, widget.fileName));
      await file.writeAsBytes(await receiptPdfBytes(widget.text), flush: true);
      await NativeCore.printPdf(file.path, printer: _selected ?? '');
      if (mounted) {
        Navigator.of(context).pop();
        showToast(context, 'Sent to Windows printing');
      }
    } catch (e) {
      setState(() => _busy = false);
      if (mounted)
        showToast(context, 'Windows could not print it. $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SoraDialog(
      title: 'Print or save',
      subtitle: 'No printer is set for this receipt, so choose one now.',
      icon: Icons.print_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_printers.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: p.raised,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: p.hairline),
              ),
              child: Text(
                'Windows has no printers installed. Save the receipt as a PDF instead.',
                style: TextStyle(fontSize: 12, color: p.muted, height: 1.4),
              ),
            )
          else
            SoraSelect<String>(
              label: 'Printer',
              value: _selected ?? _printers.first,
              icon: Icons.print_rounded,
              options: _printers.map((e) => SoraSelectOption(e, e)).toList(),
              onChanged: (v) => setState(() => _selected = v),
            ),
          const SizedBox(height: 16),
          GlassButton(
            label: 'Send to the printer',
            icon: Icons.print_rounded,
            primary: true,
            expand: true,
            loading: _busy,
            onPressed: _printers.isEmpty ? null : _print,
          ),
          const SizedBox(height: 8),
          GlassButton(
            label: 'Use the Windows PDF / printing driver',
            icon: Icons.output_rounded,
            expand: true,
            onPressed: _busy ? null : _systemPrint,
          ),
          const SizedBox(height: 8),
          GlassButton(
            label: 'Save as PDF…',
            icon: Icons.picture_as_pdf_outlined,
            expand: true,
            onPressed: () async {
              await saveReceiptPdf(
                context,
                widget.store,
                widget.text,
                widget.fileName,
              );
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      actions: [
        GlassButton(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
