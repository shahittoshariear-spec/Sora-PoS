import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../analytics.dart';
import '../format.dart';
import '../models.dart';
import '../store.dart';

const int receiptColumns = 32;

String lineOf(String left, String right, {int width = receiptColumns}) {
  final available = width - right.length - 1;
  if (left.length >= available) {
    return '${left.substring(0, available.clamp(0, left.length)).trimRight()} $right';
  }
  return '${left.padRight(available)} $right';
}

String centred(String text, {int width = receiptColumns}) {
  if (text.length >= width) return text;
  final pad = ((width - text.length) / 2).floor();
  return '${' ' * pad}$text';
}

List<String> wrapText(String text, int width) {
  final words = text.trim().split(RegExp(r'\s+'));
  final lines = <String>[];
  var current = '';
  for (final word in words) {
    if (current.isEmpty) {
      current = word;
    } else if ((current.length + 1 + word.length) <= width) {
      current = '$current $word';
    } else {
      lines.add(current);
      current = word;
    }
    while (current.length > width) {
      lines.add(current.substring(0, width));
      current = current.substring(width);
    }
  }
  if (current.isNotEmpty) lines.add(current);
  return lines;
}

String _dash([int width = receiptColumns]) => '-' * width;

List<String> _headerLines(Store store, String title, {String? extra}) {
  final s = store.data.shop;
  final out = <String>[
    centred(s.name.toUpperCase()),
  ];
  for (final line in s.address.split('\n')) {
    if (line.trim().isNotEmpty) out.add(centred(line.trim()));
  }
  if (s.phone.trim().isNotEmpty) out.add(centred(s.phone.trim()));
  out.add(_dash());
  out.add(centred(title));
  if (extra != null) out.add(centred(extra));
  out.add(_dash());
  return out;
}

List<String> _itemLines(SaleLine line) {
  final out = <String>[];
  final qty = numText(line.qty).padLeft(3);
  final money = moneyPlain(line.total).padLeft(9);
  final nameWidth = receiptColumns - 4 - 10;
  final name = line.name.length > nameWidth ? line.name.substring(0, nameWidth) : line.name;
  out.add('$qty ${name.padRight(nameWidth)}$money');
  if (line.qty != 1) {
    final each = '  @ ${moneyPlain(line.unitPrice)} each';
    out.add(each);
  }
  if (line.name.length > nameWidth) {
    for (final extra in wrapText(line.name.substring(nameWidth), nameWidth)) {
      out.add('    ${extra.padRight(nameWidth)}$money'.replaceFirst(money, ''.padLeft(9)));
    }
  }
  return out;
}

String saleReceiptText(Store store, Sale sale, {bool reprint = false}) {
  final s = store.data.shop;
  final out = <String>[
    ..._headerLines(store, reprint ? 'REPRINT' : 'RECEIPT'),
    lineOf('Receipt #${sale.number}', timeShort(sale.at)),
    lineOf(dateMedium(sale.at), ''),
    lineOf('Cashier: ${sale.cashierName}', ''),
    _dash(),
    'Qty Item              Total',
    _dash(),
  ];
  for (final line in sale.lines) {
    out.addAll(_itemLines(line));
  }
  out.add(_dash());
  out.add(lineOf('Subtotal', moneyPlain(sale.subtotal)));
  if (s.taxRate > 0) out.add(lineOf('Tax (${numText(s.taxRate)}%)', moneyPlain(sale.tax)));
  out.add(lineOf('TOTAL', '${s.currency}${moneyPlain(sale.total)}'));
  if (sale.card > 0 && sale.cash > 0) {
    out.add(lineOf('Card', moneyPlain(sale.card)));
    out.add(lineOf('Cash', moneyPlain(sale.cash)));
  } else if (sale.card > 0) {
    out.add(lineOf('Card', moneyPlain(sale.card)));
  } else {
    out.add(lineOf('Cash', moneyPlain(sale.cashTendered == 0 ? sale.cash : sale.cashTendered)));
    if (sale.change > 0) out.add(lineOf('Change', moneyPlain(sale.change)));
  }
  if (sale.voided) {
    out.add(_dash());
    out.add(centred('*** VOID ***'));
    if (sale.voidedByName != null) out.add(centred('by ${sale.voidedByName}'));
  }
  out.add(_dash());
  if (s.receiptFooter.trim().isNotEmpty) {
    for (final line in wrapText(s.receiptFooter, receiptColumns)) {
      out.add(centred(line));
    }
  }
  out.add(centred('Sora PoS'));
  out.add('');
  out.add('');
  return out.join('\n');
}

String liveReceiptText(
  Store store,
  List<SaleLine> lines,
  CartTotals totals, {
  required int number,
  String cashier = '',
}) {
  final s = store.data.shop;
  final now = DateTime.now();
  final out = <String>[
    ..._headerLines(store, 'LIVE RECEIPT'),
    lineOf('Sale #$number', timeShort(now)),
    lineOf(dateMedium(now), ''),
    if (cashier.isNotEmpty) lineOf('Cashier: $cashier', ''),
    _dash(),
    'Qty Item              Total',
    _dash(),
  ];
  if (lines.isEmpty) {
    out.add(centred('Nothing in the sale yet.'));
  } else {
    for (final line in lines) {
      out.addAll(_itemLines(line));
    }
  }
  out.addAll([
    _dash(),
    lineOf('Subtotal', moneyPlain(totals.subtotal)),
    if (s.taxRate > 0) lineOf('Tax (${numText(s.taxRate)}%)', moneyPlain(totals.tax)),
    lineOf('TOTAL', '${s.currency}${moneyPlain(totals.total)}'),
    _dash(),
    centred('*** NOT PAID ***'),
    _dash(),
  ]);
  if (s.receiptFooter.trim().isNotEmpty) {
    for (final line in wrapText(s.receiptFooter, receiptColumns)) {
      out.add(centred(line));
    }
  }
  out.add('');
  return out.join('\n');
}

String refundReceiptText(Store store, RefundRecord refund, {bool reprint = false}) {
  final s = store.data.shop;
  final out = <String>[
    ..._headerLines(store, reprint ? 'REFUND REPRINT' : 'REFUND'),
    lineOf('Refund #${refund.number}', timeShort(refund.at)),
    lineOf('Of sale #${refund.saleNumber}', dateMedium(refund.at)),
    lineOf('Cashier: ${refund.cashierName}', ''),
    if (refund.authorisedBy.isNotEmpty) lineOf('Approved by: ${refund.authorisedBy}', ''),
    _dash(),
    'Qty Item              Total',
    _dash(),
  ];
  for (final line in refund.lines) {
    out.addAll(_itemLines(line));
  }
  out.add(_dash());
  out.add(lineOf('Subtotal', moneyPlain(refund.subtotal)));
  if (s.taxRate > 0) out.add(lineOf('Tax', moneyPlain(refund.tax)));
  out.add(lineOf('REFUNDED', '${s.currency}${moneyPlain(refund.total)}'));
  if (refund.card > 0 && refund.cash > 0) {
    out.add(lineOf('Cash', moneyPlain(refund.cash)));
    out.add(lineOf('Card', moneyPlain(refund.card)));
  } else {
    out.add(lineOf(refund.method, moneyPlain(refund.total)));
  }
  if ((refund.reason ?? '').trim().isNotEmpty) {
    out.add(_dash());
    for (final line in wrapText(refund.reason!, receiptColumns)) {
      out.add(line);
    }
  }
  out.add(_dash());
  out.add(centred('Money returned with our apologies.'));
  out.add('');
  out.add('');
  return out.join('\n');
}

/// ESC/POS with the accents the shop is most likely to type, and a clean
/// fallback for anything else. The printer gets exactly this text.
const _charMap = <String, String>{
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
  'Á': 'A', 'À': 'A', 'Â': 'A', 'Ä': 'A', 'Ã': 'A', 'Å': 'A',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'Í': 'I', 'Ì': 'I', 'Î': 'I', 'Ï': 'I',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'Ó': 'O', 'Ò': 'O', 'Ô': 'O', 'Ö': 'O', 'Õ': 'O',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Ü': 'U',
  'ñ': 'n', 'Ñ': 'N', 'ç': 'c', 'Ç': 'C',
  '–': '-', '—': '-', '‘': "'", '’': "'", '“': '"', '”': '"',
  '…': '...', '•': '*', '½': '1/2', '¼': '1/4', '£': 'GBP', '€': 'EUR',
};

String asciiClean(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (rune >= 32 && rune < 127) {
      buffer.write(char);
    } else if (char == '\n' || char == '\r') {
      buffer.write(char);
    } else if (_charMap.containsKey(char)) {
      buffer.write(_charMap[char]);
    } else {
      buffer.write('?');
    }
  }
  return buffer.toString();
}

Uint8List escPosBytes(String text, {bool cut = false}) {
  final bytes = <int>[];
  // Initialise, then centre the shop's name at double size.
  bytes.addAll([0x1B, 0x40]);
  bytes.addAll([0x1B, 0x61, 0x01]);
  bytes.addAll([0x1D, 0x21, 0x11]);
  final lines = asciiClean(text).split('\n');
  if (lines.isNotEmpty) {
    bytes.addAll(latin1.encode('${lines.first}\n'));
    bytes.addAll([0x1D, 0x21, 0x00]);
    for (var i = 1; i < lines.length; i++) {
      bytes.addAll(latin1.encode('${lines[i]}\n'));
    }
  }
  bytes.addAll([0x1B, 0x61, 0x00]);
  if (cut) {
    bytes.addAll([0x1D, 0x56, 0x42, 0x00]);
  }
  return Uint8List.fromList(bytes);
}

Future<Uint8List> receiptPdfBytes(String text) async {
  final doc = pw.Document(compress: true);
  final format = PdfPageFormat(80 * PdfPageFormat.mm, 297 * PdfPageFormat.mm,
      marginLeft: 6 * PdfPageFormat.mm,
      marginRight: 6 * PdfPageFormat.mm,
      marginTop: 6 * PdfPageFormat.mm,
      marginBottom: 8 * PdfPageFormat.mm);
  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      build: (context) => [
        pw.Text(
          asciiClean(text),
          style: pw.TextStyle(font: pw.Font.courier(), fontSize: 8.5, lineSpacing: 1.2),
        ),
      ],
    ),
  );
  return doc.save();
}

String testReceiptText(Store store, {String printer = ''}) {
  final s = store.data.shop;
  final out = <String>[
    centred(s.name.toUpperCase()),
    centred('Printer test'),
    _dash(),
    centred('If you can read this,'),
    centred('the printer is ready.'),
    _dash(),
    lineOf('Printer', printer.isEmpty ? 'default' : printer),
    lineOf('Time', timeShort(DateTime.now())),
    lineOf('Date', dateKey(DateTime.now())),
    _dash(),
    centred('Sora PoS'),
    '',
    '',
  ];
  return out.join('\n');
}
