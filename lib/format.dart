import 'package:intl/intl.dart';

final NumberFormat _moneyFormat = NumberFormat('#,##0.00', 'en_US');
final NumberFormat _intFormat = NumberFormat('#,##0', 'en_US');

String money(double value, [String symbol = 'R']) {
  final body = _moneyFormat.format(value.abs());
  return value < 0 ? '-$symbol$body' : '$symbol$body';
}

String moneyPlain(double value) => _moneyFormat.format(value);

String numText(double value) {
  if (value == value.roundToDouble()) return _intFormat.format(value);
  return _moneyFormat.format(value);
}

String compactNumber(num value) {
  final v = value.toDouble();
  if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}m';
  if (v.abs() >= 10000) return '${(v / 1000).toStringAsFixed(1)}k';
  return _intFormat.format(v);
}

String dateLong(DateTime d) => DateFormat('EEEE, d MMMM yyyy').format(d);
String dateMedium(DateTime d) => DateFormat('d MMM yyyy').format(d);
String dateShort(DateTime d) => DateFormat('dd/MM/yy').format(d);
String dayMonth(DateTime d) => DateFormat('d MMM').format(d);
String monthYear(DateTime d) => DateFormat('MMMM yyyy').format(d);
String timeShort(DateTime d) => DateFormat('HH:mm').format(d);
String timeExact(DateTime d) => DateFormat('HH:mm:ss').format(d);
String weekdayShort(DateTime d) => DateFormat('EEE').format(d);

String greeting(DateTime now) {
  final h = now.hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

String plural(num n, String singular, [String? plural]) =>
    n == 1 ? singular : (plural ?? '${singular}s');
