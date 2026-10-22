import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../analytics.dart';
import '../format.dart';
import '../models.dart';
import '../store.dart';
import 'receipts.dart';

pw.TextStyle _body({bool bold = false, double size = 9, PdfColor? color}) => pw.TextStyle(
      font: bold ? pw.Font.helveticaBold() : pw.Font.helvetica(),
      fontSize: size,
      color: color,
      lineSpacing: 1.25,
    );

String _hexOf(int value) => '#${value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

PdfColor _accent(Store store) {
  final color = store.data.appearance.themeId.startsWith('custom')
      ? 0xFF2DD4BF
      : 0xFF2DD4BF;
  return PdfColor.fromHex(_hexOf(color));
}

String _safe(String value) => asciiClean(value);

Future<Uint8List> dayReportPdf(Store store, DateTime day) async {
  final totals = totalsForDay(store.data, day);
  final start = startOfDay(day);
  final end = start.add(const Duration(days: 1));
  final voids = store.data.sales
      .where((s) => s.voided && s.voidedAt != null && !s.voidedAt!.isBefore(start) && s.voidedAt!.isBefore(end))
      .toList()
    ..sort((a, b) => a.voidedAt!.compareTo(b.voidedAt!));
  final changes = store.data.audit
      .where((a) => !a.at.isBefore(start) && a.at.isBefore(end))
      .toList()
    ..sort((a, b) => a.at.compareTo(b.at));
  final discrepancies = unaccountedStock(store.data, day);
  final sellers = topSellers(store.data, start, end, limit: 8);
  final first = totals.saleList.isEmpty
      ? null
      : totals.saleList.reduce((a, b) => a.at.isBefore(b.at) ? a : b).at;
  final last = totals.saleList.isEmpty
      ? null
      : totals.saleList.reduce((a, b) => a.at.isAfter(b.at) ? a : b).at;
  final cashRefunded = round2(totals.refundList.fold(0.0, (a, r) => a + r.cash));
  final drawer = round2(totals.cash - cashRefunded);
  final accent = _accent(store);
  final currency = store.data.shop.currency;

  final doc = pw.Document(compress: true);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(38, 34, 38, 34),
      theme: pw.ThemeData.withFont(base: pw.Font.helvetica(), bold: pw.Font.helveticaBold()),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(_safe(store.data.shop.name), style: _body(bold: true, size: 20)),
                  if (store.data.shop.address.isNotEmpty)
                    pw.Text(_safe(store.data.shop.address.replaceAll('\n', ', ')), style: _body(size: 8.5, color: PdfColors.grey700)),
                  if (store.data.shop.phone.isNotEmpty)
                    pw.Text(_safe(store.data.shop.phone), style: _body(size: 8.5, color: PdfColors.grey700)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('DAY REPORT', style: _body(bold: true, size: 12, color: accent)),
                  pw.Text(dateLong(day), style: _body(bold: true, size: 10)),
                  pw.Text('Built ${timeShort(DateTime.now())}', style: _body(size: 8, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Container(height: 1.2, color: accent),
          pw.SizedBox(height: 14),
        ],
      ),
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Sora PoS  -  ${_safe(store.data.shop.name)}', style: _body(size: 7.5, color: PdfColors.grey500)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: _body(size: 7.5, color: PdfColors.grey500)),
          ],
        ),
      ),
      build: (context) => [
        pw.Row(
          children: [
            _metric('SALES', '$currency${moneyPlain(totals.sales)}', accent),
            pw.SizedBox(width: 8),
            _metric('REFUNDS', '$currency${moneyPlain(totals.refunds)}', PdfColors.red700),
            pw.SizedBox(width: 8),
            _metric('NET', '$currency${moneyPlain(totals.net)}', PdfColors.green700),
            pw.SizedBox(width: 8),
            _metric('PROFIT', '$currency${moneyPlain(totals.profit)}', PdfColors.blueGrey800),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            _metric('TRANSACTIONS', '${totals.transactions}', PdfColors.grey800),
            pw.SizedBox(width: 8),
            _metric('ITEMS SOLD', moneyPlain(totals.items), PdfColors.grey800),
            pw.SizedBox(width: 8),
            _metric('AVERAGE SALE', '$currency${moneyPlain(totals.averageSale)}', PdfColors.grey800),
            pw.SizedBox(width: 8),
            _metric('TAX', '$currency${moneyPlain(totals.tax)}', PdfColors.grey800),
          ],
        ),
        pw.SizedBox(height: 18),
        _heading('The day', accent),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _kv('First sale', first == null ? '-' : timeShort(first)),
                  _kv('Last sale', last == null ? '-' : timeShort(last)),
                  _kv('Cash taken', '$currency${moneyPlain(totals.cash)}'),
                  _kv('Card taken', '$currency${moneyPlain(totals.card)}'),
                  _kv('Cash refunded', '$currency${moneyPlain(cashRefunded)}'),
                  _kv('Expected in drawer', '$currency${moneyPlain(drawer)}', bold: true, color: accent),
                ],
              ),
            ),
            pw.SizedBox(width: 26),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _kv('Voids', '${voids.length}'),
                  _kv('Refunds', '${totals.refundList.length}'),
                  _kv('Inventory at cost', '$currency${moneyPlain(inventoryValueAtCost(store.data))}'),
                  _kv('Inventory at sell', '$currency${moneyPlain(inventoryValueAtSell(store.data))}'),
                  _kv('Low stock items', '${lowStockProducts(store.data).length}'),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        _heading('Top sellers', accent),
        if (sellers.isEmpty)
          pw.Text('No items were sold.', style: _body(size: 8.5, color: PdfColors.grey600))
        else
          pw.TableHelper.fromTextArray(
            headers: ['Item', 'Qty', 'Takings'],
            data: sellers.map((s) => [_safe(s.name), numText(s.qty), '$currency${moneyPlain(s.revenue)}']).toList(),
            headerStyle: _body(bold: true, size: 8, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: accent),
            cellStyle: _body(size: 8.2),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            border: null,
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            columnWidths: {
              0: const pw.FlexColumnWidth(4),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1.5),
            },
          ),
        if (voids.isNotEmpty) ...[
          pw.SizedBox(height: 18),
          _heading('Voids', PdfColors.red700),
          pw.TableHelper.fromTextArray(
            headers: ['Receipt', 'Voided', 'Total', 'Cashier', 'Voided by'],
            data: voids
                .map((s) => [
                      '#${s.number}',
                      timeShort(s.voidedAt!),
                      '$currency${moneyPlain(s.total)}',
                      _safe(s.cashierName),
                      _safe(s.voidedByName ?? ''),
                    ])
                .toList(),
            headerStyle: _body(bold: true, size: 8, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: PdfColors.red700),
            cellStyle: _body(size: 8.2, color: PdfColors.red800),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            border: null,
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.red50),
          ),
        ],
        pw.SizedBox(height: 18),
        _heading('Changes the takings cannot account for', PdfColors.red700),
        if (changes.isEmpty)
          pw.Text('Nothing was changed by hand.', style: _body(size: 8.5, color: PdfColors.grey600))
        else ...[
          pw.Text(
            'These changes were made quietly, without a sale behind them.',
            style: _body(size: 7.8, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 5),
          pw.TableHelper.fromTextArray(
            headers: ['Time', 'What happened', 'By'],
            data: changes
                .map((a) => [timeShort(a.at), _safe('${a.title} - ${a.detail}'), _safe(a.by ?? '')])
                .toList(),
            headerStyle: _body(bold: true, size: 8, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: PdfColors.red700),
            cellStyle: _body(size: 7.8, color: PdfColors.red800),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
            border: null,
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.red50),
            columnWidths: {
              0: const pw.FlexColumnWidth(0.8),
              1: const pw.FlexColumnWidth(5),
              2: const pw.FlexColumnWidth(1.4),
            },
          ),
        ],
        pw.SizedBox(height: 18),
        _heading('Stock no sale explains', PdfColors.red700),
        if (discrepancies.isEmpty)
          pw.Text(
            'The shelf agrees with the last report and every sale since.',
            style: _body(size: 8.5, color: PdfColors.grey600),
          )
        else
          pw.TableHelper.fromTextArray(
            headers: ['Product', 'Expected', 'Found', 'Difference'],
            data: discrepancies
                .map((d) => [
                      _safe(d.product.name),
                      numText(d.expected),
                      numText(d.found),
                      '${d.difference > 0 ? '+' : ''}${numText(d.difference)}',
                    ])
                .toList(),
            headerStyle: _body(bold: true, size: 8, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: PdfColors.red700),
            cellStyle: _body(size: 8.2, color: PdfColors.red800),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            border: null,
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.red50),
            columnWidths: {
              0: const pw.FlexColumnWidth(4),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1),
            },
          ),
        pw.SizedBox(height: 20),
        pw.Divider(color: PdfColors.grey300, height: 1),
        pw.SizedBox(height: 6),
        pw.Text(
          'The sales history for this day travels beside this report as its own PDF. '
          'Every figure above is calculated from the same records at the same moment.',
          style: _body(size: 7.5, color: PdfColors.grey600),
        ),
      ],
    ),
  );
  return doc.save();
}

pw.Widget _metric(String label, String value, PdfColor color) => pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey50,
          border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: _body(bold: true, size: 6.5, color: PdfColors.grey600)),
            pw.SizedBox(height: 3),
            pw.Text(value, style: _body(bold: true, size: 11.5, color: color)),
          ],
        ),
      ),
    );

pw.Widget _heading(String text, PdfColor color) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(text.toUpperCase(), style: _body(bold: true, size: 9, color: color)),
    );

pw.Widget _kv(String label, String value, {bool bold = false, PdfColor? color}) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 105,
            child: pw.Text(label, style: _body(size: 8.2, color: PdfColors.grey700)),
          ),
          pw.Text(value, style: _body(bold: bold, size: 8.4, color: color ?? PdfColors.grey900)),
        ],
      ),
    );

Future<Uint8List> salesHistoryPdf(Store store, DateTime day) async {
  final totals = totalsForDay(store.data, day);
  final lines = lineHistory(store.data, day: day);
  final accent = _accent(store);
  final currency = store.data.shop.currency;
  final doc = pw.Document(compress: true);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 30, 32, 30),
      theme: pw.ThemeData.withFont(base: pw.Font.helvetica(), bold: pw.Font.helveticaBold()),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(_safe(store.data.shop.name), style: _body(bold: true, size: 17)),
                  pw.Text('Sales history - item by item', style: _body(size: 9, color: PdfColors.grey700)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(dateLong(day), style: _body(bold: true, size: 10)),
                  pw.Text(
                    '$currency${moneyPlain(totals.net)} net across ${totals.transactions} sales',
                    style: _body(size: 8, color: PdfColors.grey600),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 9),
          pw.Container(height: 1.1, color: accent),
          pw.SizedBox(height: 10),
        ],
      ),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Sora PoS  -  sales history', style: _body(size: 7.5, color: PdfColors.grey500)),
          pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: _body(size: 7.5, color: PdfColors.grey500)),
        ],
      ),
      build: (context) => [
        if (lines.isEmpty)
          pw.Text('No items were sold on this day.', style: _body(size: 10, color: PdfColors.grey600))
        else
          pw.Table(
            border: null,
            columnWidths: {
              0: const pw.FlexColumnWidth(0.8),
              1: const pw.FlexColumnWidth(0.9),
              2: const pw.FlexColumnWidth(4),
              3: const pw.FlexColumnWidth(0.7),
              4: const pw.FlexColumnWidth(1.1),
              5: const pw.FlexColumnWidth(1.1),
              6: const pw.FlexColumnWidth(1.1),
              7: const pw.FlexColumnWidth(1.4),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: accent),
                children: [
                  _cell('Time', header: true),
                  _cell('Receipt', header: true),
                  _cell('Item', header: true),
                  _cell('Qty', header: true),
                  _cell('Price', header: true),
                  _cell('Line', header: true),
                  _cell('Payment', header: true),
                  _cell('Rung up by', header: true),
                ],
              ),
              for (var i = 0; i < lines.length; i++)
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: lines[i].isRefund
                        ? PdfColors.red50
                        : (i.isEven ? PdfColors.grey50 : PdfColors.white),
                  ),
                  children: [
                    _cell(timeShort(lines[i].at), refund: lines[i].isRefund),
                    _cell(
                      lines[i].isRefund ? '#${lines[i].number}R' : '#${lines[i].number}',
                      refund: lines[i].isRefund,
                    ),
                    _cell(_safe(lines[i].line.name), refund: lines[i].isRefund),
                    _cell(numText(lines[i].line.qty), refund: lines[i].isRefund),
                    _cell(moneyPlain(lines[i].line.unitPrice), refund: lines[i].isRefund),
                    _cell(
                      '${lines[i].isRefund ? '-' : ''}$currency${moneyPlain(lines[i].line.total)}',
                      refund: lines[i].isRefund,
                      bold: true,
                    ),
                    _cell(lines[i].isRefund ? 'Refund' : lines[i].payment, refund: lines[i].isRefund),
                    _cell(
                      _safe(lines[i].authorisedBy == null
                          ? lines[i].cashier
                          : '${lines[i].cashier} (ok: ${lines[i].authorisedBy})'),
                      refund: lines[i].isRefund,
                    ),
                  ],
                ),
            ],
          ),
      ],
    ),
  );
  return doc.save();
}

pw.Widget _cell(String text, {bool header = false, bool refund = false, bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3.2),
      child: pw.Text(
        text,
        style: _body(
          bold: header || bold,
          size: header ? 7.2 : 7.4,
          color: header
              ? PdfColors.white
              : refund
                  ? PdfColors.red800
                  : PdfColors.grey900,
        ),
      ),
    );
