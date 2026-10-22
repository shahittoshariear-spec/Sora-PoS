import 'dart:io';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import '../analytics.dart';
import '../format.dart';
import '../models.dart';
import '../store.dart';
import 'native.dart';
import 'paths.dart';
import 'report_pdf.dart';

class EmailOutcome {
  final bool ok;
  final String message;
  final String? journalPath;
  const EmailOutcome(this.ok, this.message, {this.journalPath});
}

class EmailService {
  static bool _sending = false;

  static Future<EmailOutcome> sendDayReport(Store store, DateTime day) async {
    if (_sending) {
      return const EmailOutcome(false, 'A report is already being sent.');
    }
    final email = store.data.settings.emailAddress.trim();
    if (email.isEmpty) {
      return const EmailOutcome(false, 'Add the shop’s Gmail address in Setup → Email first.');
    }
    final password = await NativeCore.readSmtpPassword();
    if (password == null || password.isEmpty) {
      return const EmailOutcome(false, 'Save the Google App Password in Setup → Email first.');
    }

    _sending = true;
    final tempFiles = <File>[];
    try {
      final report = await dayReportPdf(store, day);
      final history = await salesHistoryPdf(store, day);
      final watch = watchListFor(store.data, day);
      final tmp = Directory(joinPath(store.rootDir.path, 'tmp'));
      await tmp.create(recursive: true);
      final stamp = dateKey(day);
      final reportFile = File(joinPath(tmp.path, 'day-report-$stamp.pdf'));
      final historyFile = File(joinPath(tmp.path, 'sales-history-$stamp.pdf'));
      await reportFile.writeAsBytes(report, flush: true);
      await historyFile.writeAsBytes(history, flush: true);
      tempFiles.addAll([reportFile, historyFile]);

      final message = Message()
        ..from = Address(email, store.data.shop.name)
        ..recipients.add(email)
        ..subject = 'Sora PoS day report · ${dateLong(day)} · ${store.data.shop.name}'
        ..text = 'Attached is the day report and the day’s sales history, item by item.\n\n'
            'Sales: ${store.fmt(totalsForDay(store.data, day).sales)}\n'
            'Transactions: ${totalsForDay(store.data, day).transactions}\n\n'
            '${_watchText(watch)}\n\n'
            'Sent by Sora PoS.'
        ..html = _bodyHtml(store, day, watch)
        ..attachments = [
          FileAttachment(reportFile, contentType: 'application/pdf'),
          FileAttachment(historyFile, contentType: 'application/pdf'),
        ];

      final server = SmtpServer(
        'smtp.gmail.com',
        port: 465,
        ssl: true,
        username: email,
        password: password,
      );
      await send(message, server, timeout: const Duration(seconds: 45));
      final journal = await store.writeSalesJournal(day);
      await store.captureSnapshot(day);
      await store.markReportSent(day);
      return EmailOutcome(true, 'The day report and sales history are on their way to $email.', journalPath: journal);
    } catch (e) {
      store.queueReport(dateKey(day));
      return EmailOutcome(false, 'The report could not be sent. It is queued and will be tried again while Sora stays open.\n$e');
    } finally {
      for (final f in tempFiles) {
        try {
          await f.delete();
        } catch (_) {}
      }
      _sending = false;
    }
  }

  /// Called once a minute by the app. Nothing leaves the computer unless the
  /// owner has asked for the report to send itself, and a missing connection
  /// simply leaves the report queued.
  static Future<void> tick(Store store) async {
    if (_sending) return;
    final settings = store.data.settings;
    final todayKey = dateKey(DateTime.now());
    final alreadyToday = settings.lastReportSentDate == todayKey;
    final pending = List<String>.from(settings.pendingReports);

    if (settings.autoEmail && !alreadyToday && !pending.contains(todayKey)) {
      final parts = settings.emailTime.split(':');
      final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 17;
      final minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 30;
      final now = DateTime.now();
      final due = DateTime(now.year, now.month, now.day, hour, minute);
      if (now.isAfter(due)) pending.add(todayKey);
    }

    if (pending.isEmpty) return;
    pending.sort();
    final dayText = pending.first;
    final parsed = DateTime.tryParse(dayText);
    if (parsed == null) {
      store.data.settings.pendingReports.remove(dayText);
      await store.saveNow();
      return;
    }
    final password = await NativeCore.readSmtpPassword();
    if (password == null || password.isEmpty || settings.emailAddress.trim().isEmpty) {
      return; // Wait quietly until the shop has filled in its mail details.
    }
    await sendDayReport(store, parsed);
  }

  /// Events the owner wants to see every day, in red: things that reached the
  /// till and did not become a sale, and stock or prices changed by hand.
  static const watchKinds = {
    'cart_removed',
    'held_discard',
    'held_stale',
    'stock_edit',
    'price_change',
    'cost_change',
    'product_delete',
    'price_override',
    'void',
  };

  static List<AuditEntry> watchListFor(AppData data, DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return data.audit
        .where((e) => !e.at.isBefore(start) && e.at.isBefore(end) && watchKinds.contains(e.kind))
        .toList()
      ..sort((a, b) => a.at.compareTo(b.at));
  }

  static String _esc(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _watchText(List<AuditEntry> watch) {
    if (watch.isEmpty) return 'Nothing left the till, and no stock was changed by hand.';
    final buffer = StringBuffer('WATCH LIST — check the camera against these times:\n');
    for (final entry in watch) {
      buffer.writeln('${timeExact(entry.at)} · ${entry.title} · ${entry.detail} · ${entry.by ?? ''}');
    }
    return buffer.toString().trimRight();
  }

  static String _bodyHtml(Store store, DateTime day, List<AuditEntry> watch) {
    final totals = totalsForDay(store.data, day);
    final rows = watch
        .map(
          (entry) => '<tr>'
              '<td style="padding:7px 10px 7px 0;vertical-align:top;white-space:nowrap;font:800 13px Arial,sans-serif;color:#B3121B;">${timeExact(entry.at)}</td>'
              '<td style="padding:7px 0;vertical-align:top;font:700 13px Arial,sans-serif;color:#B3121B;">${_esc(entry.title)}'
              '<div style="margin-top:2px;font:400 12px Arial,sans-serif;color:#8C1118;">${_esc(entry.detail)}</div>'
              '<div style="margin-top:2px;font:700 11px Arial,sans-serif;color:#B3121B;">${_esc(entry.by ?? '')}</div>'
              '</td>'
              '</tr>',
        )
        .join();
    final watchBlock = watch.isEmpty
        ? '<div style="margin-top:22px;font:400 12px Arial,sans-serif;color:#5D6675;">Nothing left the till, and no stock was changed by hand.</div>'
        : '<div style="margin-top:24px;padding:14px 18px 16px;border:2px solid #B3121B;border-radius:10px;">'
            '<div style="font:800 15px Arial,sans-serif;letter-spacing:.4px;color:#B3121B;">WATCH LIST</div>'
            '<div style="margin:3px 0 8px;font:400 11px Arial,sans-serif;color:#8C1118;">Items that left the till before payment, held sales thrown away, and stock or prices changed by hand. Check the camera against these times.</div>'
            '<table cellspacing="0" cellpadding="0" style="border-collapse:collapse;width:100%;">$rows</table>'
            '</div>';
    return '<div style="background:#F4F6FA;padding:28px 20px;">'
        '<div style="max-width:620px;margin:0 auto;background:#FFFFFF;border-radius:12px;padding:28px 30px;">'
        '<div style="font:800 20px Arial,sans-serif;color:#101828;letter-spacing:-.3px;">${_esc(store.data.shop.name)}</div>'
        '<div style="margin-top:4px;font:400 13px Arial,sans-serif;color:#5D6675;">${dateLong(day)} · day report</div>'
        '<div style="margin-top:18px;font:400 13px Arial,sans-serif;color:#101828;">'
        'Sales <b>${store.fmt(totals.sales)}</b> across <b>${totals.transactions}</b> transactions.'
        '</div>'
        '<div style="margin-top:8px;font:400 12px Arial,sans-serif;color:#5D6675;">The day report and the itemised sales history are attached as PDFs.</div>'
        '$watchBlock'
        '<div style="margin-top:22px;font:400 11px Arial,sans-serif;color:#8C94A3;">Sent by Sora PoS.</div>'
        '</div></div>';
  }
}
