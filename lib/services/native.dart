import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'paths.dart';

/// Everything in the shop that touches Windows goes through here.
///
/// The Rust helper (`sora_core.exe`) is the only native code in the app; it
/// lists and talks to printers, opens the real Windows file dialogs, keeps the
/// SMTP password in Credential Manager, and reads spreadsheets. No Flutter
/// plugin is involved, which keeps the build a plain Flutter + Cargo one.
class NativeCore {
  static String? _exe;
  static bool _preparing = false;

  static String get _binDir => joinPath(soraDataDirectory().path, 'bin');
  static String get _tmpDir => joinPath(soraDataDirectory().path, 'tmp');

  static Future<String> executable() async {
    if (_exe != null) return _exe!;
    await _ensurePrepared();
    final candidates = <String>[
      joinPath(_binDir, 'sora_core.exe'),
      joinPath(Directory.current.path, 'rust_core${Platform.pathSeparator}target${Platform.pathSeparator}release${Platform.pathSeparator}sora_core.exe'),
      joinPath(File(Platform.resolvedExecutable).parent.path, 'sora_core.exe'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) {
        _exe = c;
        return c;
      }
    }
    // Last resort: pull the helper out of the Flutter asset bundle.
    try {
      final data = await rootBundle.load('assets/bin/sora_core.exe');
      final dest = File(joinPath(_binDir, 'sora_core.exe'));
      await dest.parent.create(recursive: true);
      await dest.writeAsBytes(data.buffer.asUint8List(), flush: true);
      _exe = dest.path;
      return dest.path;
    } catch (_) {
      throw NativeException(
        'The Sora helper could not be found. Build it with "cargo build --release" in rust_core.',
      );
    }
  }

  static Future<void> _ensurePrepared() async {
    if (_preparing) return;
    _preparing = true;
    await Directory(_binDir).create(recursive: true);
    await Directory(_tmpDir).create(recursive: true);
    _preparing = false;
  }

  static Future<Map<String, dynamic>> run(String command, [List<String> args = const []]) async {
    final exe = await executable();
    final result = await Process.run(
      exe,
      [command, ...args],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    ).timeout(const Duration(seconds: 45), onTimeout: () {
      throw NativeException('The Sora helper took too long to answer.');
    });
    if (result.exitCode != 0) {
      final err = (result.stderr as String).trim();
      throw NativeException(err.isEmpty ? 'Native command failed: $command' : err);
    }
    final out = (result.stdout as String).trim();
    if (out.isEmpty) return {};
    final line = out.split('\n').last.trim();
    try {
      final decoded = jsonDecode(line);
      return decoded is Map<String, dynamic> ? decoded : {'value': decoded};
    } catch (_) {
      return {'raw': out};
    }
  }

  static Future<List<String>> printers() async {
    try {
      final r = await run('printers');
      return (r['printers'] as List? ?? []).map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<String> defaultPrinter() async {
    try {
      final r = await run('printers');
      return (r['default'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  static Future<void> printRaw(String printer, Uint8List bytes) async {
    await _ensurePrepared();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final file = File(joinPath(_tmpDir, 'receipt-$stamp.bin'));
    await file.writeAsBytes(bytes, flush: true);
    try {
      await run('print_raw', [printer, file.path]);
    } finally {
      unawaitedQuiet(file.delete());
    }
  }

  static Future<void> printPdf(String path, {String printer = ''}) async {
    await run('print_pdf', [path, printer]);
  }

  static Future<void> openFile(String path) async {
    await run('open_file', [path]);
  }

  static Future<String?> openDialog({String title = 'Open', String filter = 'All files|*.*'}) async {
    final r = await run('open_dialog', [title, filter]);
    final p = r['path'];
    return p == null ? null : p.toString();
  }

  static Future<String?> saveDialog({
    String title = 'Save',
    required String defaultName,
    String filter = 'All files|*.*',
  }) async {
    final r = await run('save_dialog', [title, defaultName, filter]);
    final p = r['path'];
    return p == null ? null : p.toString();
  }

  static Future<void> setWindowIcon(String themeId) async {
    try {
      final asset = 'assets/ico/icon_$themeId.ico';
      final dest = File(joinPath(joinPath(soraDataDirectory().path, 'icons'), 'icon_$themeId.ico'));
      if (!await dest.exists()) {
        final data = await rootBundle.load(asset);
        await dest.parent.create(recursive: true);
        await dest.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
      await run('set_window_icon', [dest.path]);
    } catch (_) {
      // A missing taskbar icon is never a reason to stop a sale.
    }
  }

  static Future<void> setCaptionColor(int nightColor) async {
    try {
      final hex = (nightColor & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
      await run('set_caption', [hex]);
    } catch (_) {}
  }

  static Future<void> saveSmtpPassword(String value) async {
    await run('cred_set', ['SoraPoS/smtp-app-password', value]);
  }

  static Future<String?> readSmtpPassword() async {
    try {
      final r = await run('cred_get', ['SoraPoS/smtp-app-password']);
      final v = r['value'];
      return v == null ? null : v.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<void> forgetSmtpPassword() async {
    try {
      await run('cred_delete', ['SoraPoS/smtp-app-password']);
    } catch (_) {}
  }

  static Future<ImportPreview> readSpreadsheet(String path) async {
    final r = await run('import_preview', [path]);
    return ImportPreview.fromJson(r);
  }

  static Future<List<ImportedProduct>> readProducts(String path, List<int> mapping) async {
    final r = await run('import_products', [path, mapping.join(',')]);
    return (r['products'] as List? ?? [])
        .map((e) => ImportedProduct.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static void unawaitedQuiet(Future<void> future) {
    future.catchError((_) {});
  }
}

class NativeException implements Exception {
  final String message;
  NativeException(this.message);
  @override
  String toString() => message;
}

class ImportPreview {
  final List<String> headers;
  final List<List<String>> rows;
  final int totalRows;
  final Map<String, int> mapping;
  final String sheet;

  const ImportPreview({
    required this.headers,
    required this.rows,
    required this.totalRows,
    required this.mapping,
    required this.sheet,
  });

  factory ImportPreview.fromJson(Map<String, dynamic> j) {
    final m = <String, int>{};
    final raw = j['mapping'];
    if (raw is Map) {
      raw.forEach((k, v) {
        m[k.toString()] = v is num ? v.toInt() : int.tryParse('$v') ?? -1;
      });
    }
    return ImportPreview(
      headers: (j['headers'] as List? ?? []).map((e) => e.toString()).toList(),
      rows: (j['rows'] as List? ?? [])
          .map((r) => (r as List? ?? []).map((c) => c.toString()).toList())
          .toList(),
      totalRows: (j['total_rows'] as num?)?.toInt() ?? 0,
      mapping: m,
      sheet: (j['sheet'] ?? '').toString(),
    );
  }
}

class ImportedProduct {
  final String name;
  final String sku;
  final String category;
  final double price;
  final double cost;
  final double stock;

  const ImportedProduct({
    required this.name,
    required this.sku,
    required this.category,
    required this.price,
    required this.cost,
    required this.stock,
  });

  factory ImportedProduct.fromJson(Map<String, dynamic> j) => ImportedProduct(
        name: (j['name'] ?? '').toString(),
        sku: (j['sku'] ?? '').toString(),
        category: (j['category'] ?? '').toString(),
        price: (j['price'] as num?)?.toDouble() ?? 0,
        cost: (j['cost'] as num?)?.toDouble() ?? 0,
        stock: (j['stock'] as num?)?.toDouble() ?? 0,
      );
}
