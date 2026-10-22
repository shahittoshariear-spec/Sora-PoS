import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';

/// Asks an owner or manager to approve something a cashier started.
/// A signed-in manager or owner is never asked: their title is the approval.
Future<Staff?> askApproval(
  BuildContext context,
  Store store, {
  String reason = 'This needs an owner or manager.',
}) async {
  if (store.isManagerOrOwner) return store.current;
  return showSoraDialog<Staff>(
    context,
    maxWidth: 440,
    builder: (context) => _ApprovalDialog(store: store, reason: reason),
  );
}

/// A refusal that cannot be lent out, even with a password.
Future<void> ownerOnly(BuildContext context) {
  final p = context.palette;
  return showSoraDialog<void>(
    context,
    maxWidth: 430,
    builder: (context) => SoraDialog(
      title: 'Reserved for the owner',
      subtitle: 'This part of the shop belongs to the owner. A password cannot lend it out.',
      icon: Icons.lock_outline_rounded,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.raised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.hairline),
        ),
        child: Text(
          'Ask the owner to sign in.',
          style: TextStyle(color: p.muted, fontSize: 12.5),
        ),
      ),
      actions: [GlassButton(label: 'Close', onPressed: () => Navigator.of(context).pop(), primary: true)],
    ),
  );
}

class _ApprovalDialog extends StatefulWidget {
  final Store store;
  final String reason;
  const _ApprovalDialog({required this.store, required this.reason});

  @override
  State<_ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends State<_ApprovalDialog> {
  final _password = TextEditingController();
  final _focus = FocusNode();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _busy = true);
    final approver = widget.store.approve(_password.text);
    if (approver == null) {
      setState(() {
        _busy = false;
        _error = 'That password was not recognised.';
      });
      _focus.requestFocus();
      return;
    }
    Navigator.of(context).pop(approver);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SoraDialog(
      title: 'One moment',
      subtitle: widget.reason,
      icon: Icons.verified_user_outlined,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.person_outline_rounded, size: 17, color: p.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Signed in as ${widget.store.current?.name ?? 'nobody'} · ${widget.store.current?.role.label ?? ''}',
                  style: TextStyle(fontSize: 12, color: p.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SoraField(
            controller: _password,
            focusNode: _focus,
            obscure: true,
            autofocus: true,
            label: 'Owner or manager password',
            hint: 'Type the password to allow this',
            icon: Icons.key_rounded,
            error: _error,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        GlassButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        GlassButton(label: 'Allow', icon: Icons.check_rounded, primary: true, loading: _busy, onPressed: _submit),
      ],
    );
  }
}
