import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'paths.dart';

class UpdateInfo {
  final String tag;
  final String name;
  final String url;
  final String notes;

  const UpdateInfo({
    required this.tag,
    required this.name,
    required this.url,
    required this.notes,
  });
}

/// Asks GitHub for the latest public release. Failure is silent: the shop is
/// offline-first, and a missing network must never affect a sale.
Future<UpdateInfo?> checkForUpdate() async {
  HttpClient? client;
  try {
    client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    final request = await client
        .getUrl(
          Uri.parse(
            'https://api.github.com/repos/shahittoshariear-spec/Sora-PoS/releases/latest',
          ),
        )
        .timeout(const Duration(seconds: 4));
    request.headers.set(HttpHeaders.userAgentHeader, 'SoraPoS/$kAppVersion');
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.github+json',
    );
    final response = await request.close().timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) return null;
    final text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 6));
    final json = jsonDecode(text) as Map<String, dynamic>;
    final tag = (json['tag_name'] as String? ?? '').trim();
    final url = (json['html_url'] as String? ?? '').trim();
    final name = (json['name'] as String? ?? tag).trim();
    final notes = (json['body'] as String? ?? '').trim();
    if (!isNewerVersion(tag, kAppVersion)) return null;
    if (!url.startsWith('https://github.com/shahittoshariear-spec/Sora-PoS/')) {
      return null;
    }
    return UpdateInfo(tag: tag, name: name, url: url, notes: notes);
  } catch (_) {
    return null;
  } finally {
    client?.close(force: true);
  }
}

/// Compares dotted release tags such as `v5.0.1` and `5.0.2`.
bool isNewerVersion(String remote, String current) {
  List<int> parse(String value) {
    final parts = value
        .trim()
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split(RegExp(r'[.+-]'));
    return List<int>.generate(3, (i) {
      if (i >= parts.length) return 0;
      return int.tryParse(parts[i]) ?? 0;
    });
  }

  final a = parse(remote);
  final b = parse(current);
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}
