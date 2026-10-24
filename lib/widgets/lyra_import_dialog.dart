import 'package:flutter/material.dart';

import '../services/lyra_import.dart';
import '../store.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';

/// First-run import from Lyra PoS. The owner sets a new password here because
/// Lyra's unsalted password hashes cannot be carried into Sora's salted scheme.
Future<void> showLyraImportDialog(
  BuildContext context, {
  required Store store,
  required LyraImportPreview preview,
}) {
  return showSoraDialog<void>(
    context,
    maxWidth: 560,
    builder: (context) => _LyraImportDialog(store: store, preview: preview),
  );
}

class _LyraImportDialog extends StatefulWidget {
  final Store store;
  final LyraImportPreview preview;

  const _LyraImportDialog({required this.store, required this.preview});

  @override
  State<_LyraImportDialog> createState() => _LyraImportDialogState();
}

class _LyraImportDialogState extends State<_LyraImportDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _focus = FocusNode();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (_busy) return;
    final password = _password.text;
    if (password.length < 4) {
      setState(() => _error = 'Use at least four characters for the password.');
      _focus.requestFocus();
      return;
    }
    if (password != _confirm.text) {
      setState(() => _error = 'The two passwords do not match.');
      _focus.requestFocus();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = buildLyraImportData(
        widget.preview,
        ownerPassword: password,
      );
      await widget.store.importData(result.data);
      if (!mounted) return;
      Navigator.of(context).pop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.store.signIn(result.ownerId, password);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final owner = widget.preview.ownerName;
    return SoraDialog(
      title: 'Import from Lyra PoS',
      subtitle: 'Bring this shop across without typing the catalogue again.',
      icon: Icons.move_to_inbox_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.accent.withValues(alpha: 0.22)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.storefront_rounded, size: 18, color: p.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lyra PoS shop found',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: p.text,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.preview.summary,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: p.muted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            owner == null
                ? 'This file has no owner account, so it cannot be imported.'
                : 'The owner account “$owner” will keep the shop, but everyone '
                      'will need a new password. Sora cannot use Lyra’s password '
                      'hashes.',
            style: TextStyle(
              fontSize: 12,
              color: owner == null ? p.danger : p.muted,
              height: 1.5,
            ),
          ),
          if (owner != null) ...[
            const SizedBox(height: 6),
            Text(
              'Choose the owner’s new password now. Set the other people’s '
              'passwords in Setup → Staff & access after signing in.',
              style: TextStyle(fontSize: 11, color: p.faint, height: 1.45),
            ),
            const SizedBox(height: 18),
            SoraField(
              controller: _password,
              focusNode: _focus,
              autofocus: true,
              obscure: true,
              label: 'New owner password',
              hint: 'At least four characters',
              icon: Icons.key_rounded,
              error: _error,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 12),
            SoraField(
              controller: _confirm,
              obscure: true,
              label: 'Once more',
              hint: 'Repeat it',
              icon: Icons.key_rounded,
              onSubmitted: (_) => _import(),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, size: 14, color: p.faint),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'The Lyra PoS data file is left untouched. A Sora copy is '
                    'written separately.',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: p.faint,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        GlassButton(
          label: 'Cancel',
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        GlassButton(
          label: 'Import and sign in',
          icon: Icons.arrow_forward_rounded,
          primary: true,
          loading: _busy,
          onPressed: owner == null ? null : _import,
        ),
      ],
    );
  }
}
