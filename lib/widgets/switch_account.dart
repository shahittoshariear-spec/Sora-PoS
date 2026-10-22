import 'package:flutter/material.dart';

import '../cart.dart';
import '../models.dart';
import '../store.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';

/// Opens the glass sheet that lets a signed-in person hand the till to someone
/// else without closing the shop. The chosen person must type their own
/// password; an open sale is held for the person who is leaving.
Future<void> showSwitchAccountSheet(
  BuildContext context, {
  required Store store,
  required CartController cart,
}) {
  return showSoraDialog<void>(
    context,
    maxWidth: 560,
    builder: (context) => _SwitchAccountSheet(store: store, cart: cart),
  );
}

class _SwitchAccountSheet extends StatelessWidget {
  final Store store;
  final CartController cart;

  const _SwitchAccountSheet({required this.store, required this.cart});

  Future<void> _choose(BuildContext context, Staff target) async {
    final current = store.current;
    if (current == null) return;
    if (target.id == current.id) {
      Navigator.of(context).pop();
      return;
    }
    final switched = await showSoraDialog<bool>(
      context,
      maxWidth: 440,
      builder: (context) => _SwitchPasswordDialog(
        store: store,
        target: target,
        current: current,
        hasOpenSale: cart.lines.isNotEmpty,
        onSubmit: (password) => _switch(target, password),
      ),
    );
    if (switched == true && context.mounted) Navigator.of(context).pop();
  }

  Future<String?> _switch(Staff target, String password) async {
    if (!target.matches(password)) {
      return 'That password was not recognised.';
    }
    try {
      if (cart.lines.isNotEmpty) {
        await store.holdSale(
          cart.lines,
          label: 'Account switch to ${target.name}',
        );
        cart.clear();
      }
      final signed = store.signIn(target.id, password);
      if (signed == null) return 'That password was not recognised.';
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final current = store.current;
    final people = store.data.staff;
    return SoraDialog(
      title: 'Switch account',
      subtitle: 'Choose a person. Their own password is required.',
      icon: Icons.switch_account_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (people.isEmpty)
            Text(
              'No staff accounts are set up yet.',
              style: TextStyle(fontSize: 13, color: p.muted),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth >= 430;
                final width = twoColumns
                    ? (constraints.maxWidth - 10) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final person in people)
                      SizedBox(
                        width: width,
                        child: _SwitchPersonTile(
                          staff: person,
                          current: person.id == current?.id,
                          onTap: () => _choose(context, person),
                        ),
                      ),
                  ],
                );
              },
            ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                cart.lines.isEmpty
                    ? Icons.info_outline_rounded
                    : Icons.pause_circle_outline_rounded,
                size: 15,
                color: cart.lines.isEmpty ? p.faint : p.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cart.lines.isEmpty
                      ? 'Each person signs in with their own password. The shop stays open.'
                      : 'Your current sale will be held for ${current?.name ?? 'the current person'} before the switch. It can be resumed on the Till.',
                  style: TextStyle(
                    fontSize: 11,
                    color: cart.lines.isEmpty ? p.faint : p.accent,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        GlassButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _SwitchPersonTile extends StatefulWidget {
  final Staff staff;
  final bool current;
  final VoidCallback onTap;

  const _SwitchPersonTile({
    required this.staff,
    required this.current,
    required this.onTap,
  });

  @override
  State<_SwitchPersonTile> createState() => _SwitchPersonTileState();
}

class _SwitchPersonTileState extends State<_SwitchPersonTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = widget.staff;
    final roleColor = s.role == Role.owner
        ? p.accent
        : s.role == Role.manager
        ? p.accent2
        : p.muted;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: _hover ? p.accent.withValues(alpha: 0.08) : p.raised,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hover ? p.accent.withValues(alpha: 0.38) : p.hairline,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      p.accent.withValues(alpha: 0.28),
                      p.accent.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.accent.withValues(alpha: 0.22)),
                ),
                child: Text(
                  s.initials,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: p.accent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.role.label,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: roleColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.current)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    'CURRENT',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: p.accent,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 15,
                  color: _hover ? p.accent : p.faint,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchPasswordDialog extends StatefulWidget {
  final Store store;
  final Staff target;
  final Staff current;
  final bool hasOpenSale;
  final Future<String?> Function(String password) onSubmit;

  const _SwitchPasswordDialog({
    required this.store,
    required this.target,
    required this.current,
    required this.hasOpenSale,
    required this.onSubmit,
  });

  @override
  State<_SwitchPasswordDialog> createState() => _SwitchPasswordDialogState();
}

class _SwitchPasswordDialogState extends State<_SwitchPasswordDialog> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_controller.text.isEmpty) {
      setState(() => _error = 'Type the password first.');
      _focus.requestFocus();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSubmit(_controller.text);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      _focus.requestFocus();
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SoraDialog(
      title: 'Switch to ${widget.target.name}',
      subtitle: '${widget.target.role.label} · ${widget.store.data.shop.name}',
      icon: Icons.lock_open_rounded,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SoraField(
            controller: _controller,
            focusNode: _focus,
            autofocus: true,
            obscure: true,
            label: '${widget.target.name.split(' ').first}’s password',
            hint: 'Type it and press Enter',
            icon: Icons.key_rounded,
            error: _error,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                widget.hasOpenSale
                    ? Icons.pause_circle_outline_rounded
                    : Icons.info_outline_rounded,
                size: 14,
                color: widget.hasOpenSale ? p.accent : p.faint,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  widget.hasOpenSale
                      ? 'The open sale is held for ${widget.current.name}. Switch back or resume it from the Till later.'
                      : 'Signing in puts your name on every sale, refund and void.',
                  style: TextStyle(
                    fontSize: 11,
                    color: widget.hasOpenSale ? p.accent : p.faint,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        GlassButton(
          label: 'Cancel',
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        GlassButton(
          label: 'Switch',
          primary: true,
          loading: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}
