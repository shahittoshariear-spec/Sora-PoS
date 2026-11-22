import 'package:flutter/material.dart';

import '../services/native.dart';
import '../services/paths.dart';
import '../services/update_check.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';

/// A non-blocking update card. It only opens when the till is idle, so a sale
/// is never interrupted by a version check.
Future<void> showUpdatePrompt(BuildContext context, UpdateInfo info) async {
  final p = context.palette;
  final lines = info.notes
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('###'))
      .take(8)
      .toList();
  await showSoraDialog<void>(
    context,
    maxWidth: 560,
    builder: (context) => SoraDialog(
      title: 'Sora ${info.tag} is ready',
      subtitle: 'You are on $kAppVersion. The download opens in your browser.',
      icon: Icons.system_update_alt_rounded,
      accent: p.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            info.name,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: p.text,
            ),
          ),
          const SizedBox(height: 12),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: p.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      line.replaceFirst(RegExp(r'^[-*]\s*'), ''),
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.45,
                        color: p.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        GlassButton(
          label: 'Later',
          onPressed: () => Navigator.of(context).pop(),
        ),
        GlassButton(
          label: 'Open download',
          icon: Icons.open_in_new_rounded,
          primary: true,
          onPressed: () async {
            Navigator.of(context).pop();
            try {
              await NativeCore.openFile(info.url);
            } catch (_) {}
          },
        ),
      ],
    ),
  );
}

Future<void> checkUpdatesNow(BuildContext context) async {
  final info = await checkForUpdate();
  if (!context.mounted) return;
  if (info == null) {
    showToast(context, 'No newer release was found.');
    return;
  }
  await showUpdatePrompt(context, info);
}
