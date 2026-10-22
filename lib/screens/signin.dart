import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import '../ui/theme_switcher.dart';

class SignInScreen extends StatefulWidget {
  final Store store;
  const SignInScreen({super.key, required this.store});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _shop = TextEditingController(text: '');
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _shop.dispose();
    _name.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Store get store => widget.store;

  Future<void> _createShop() async {
    final shopName = _shop.text.trim();
    final ownerName = _name.text.trim();
    final password = _password.text;
    if (shopName.isEmpty) {
      setState(() => _error = 'Give your shop a name.');
      return;
    }
    if (ownerName.isEmpty) {
      setState(() => _error = 'Tell us your name.');
      return;
    }
    if (password.length < 4) {
      setState(() => _error = 'Use at least four characters for the password.');
      return;
    }
    if (password != _confirm.text) {
      setState(() => _error = 'The two passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      store.data.shop.name = shopName;
      if (store.data.categories.isEmpty) {
        store.data.categories.add(Category(id: newId(), name: 'General'));
      }
      final owner = await store.addStaff(
        name: ownerName,
        password: password,
        role: Role.owner,
      );
      await store.saveNow();
      store.signIn(owner.id, password);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _demo() async {
    setState(() => _busy = true);
    await store.seedDemo(autoSignIn: true);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hasPeople = store.data.staff.isNotEmpty;
    return AuroraBackground(
      palette: p,
      animate: !MediaQuery.disableAnimationsOf(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
              child: hasPeople ? _people(p) : _welcome(p),
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcome(SoraPalette p) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: GlassPanel(
        blur: 38,
        radius: 30,
        padding: EdgeInsets.zero,
        tint: p.isLight ? const Color(0xF2F8F9FC) : const Color(0xF20B1017),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: p.isLight
              ? [
                  Colors.white.withValues(alpha: 0.95),
                  Colors.white.withValues(alpha: 0.78),
                ]
              : [
                  const Color(0xFF1A2330).withValues(alpha: 0.92),
                  const Color(0xFF080C12).withValues(alpha: 0.96),
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 38, 40, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: ThemedMark(palette: p, size: 84)),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'Welcome to Sora',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.9,
                    color: p.text,
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Center(child: SoraSignature(palette: p, height: 17)),
              const SizedBox(height: 7),
              Center(
                child: Text(
                  'A calm, offline point of sale for your shop.\nLet’s make it yours.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.55, color: p.muted),
                ),
              ),
              const SizedBox(height: 30),
              SoraField(
                controller: _shop,
                label: 'Shop name',
                hint: 'e.g. Sora & Co.',
                icon: Icons.storefront_rounded,
              ),
              const SizedBox(height: 16),
              SoraField(
                controller: _name,
                label: 'Your name',
                hint: 'Who is setting this up?',
                icon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SoraField(
                      controller: _password,
                      label: 'Password',
                      hint: 'At least four characters',
                      icon: Icons.key_rounded,
                      obscure: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SoraField(
                      controller: _confirm,
                      label: 'Once more',
                      hint: 'Repeat it',
                      icon: Icons.key_rounded,
                      obscure: true,
                      onSubmitted: (_) => _createShop(),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: p.danger, fontSize: 12.5),
                ),
              ],
              const SizedBox(height: 24),
              GlassButton(
                label: 'Create my shop',
                icon: Icons.arrow_forward_rounded,
                primary: true,
                expand: true,
                loading: _busy,
                onPressed: _createShop,
              ),
              const SizedBox(height: 10),
              GlassPanel(
                blur: 0,
                radius: 14,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: TextButton.icon(
                  onPressed: _busy ? null : _demo,
                  icon: Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: p.accent,
                  ),
                  label: const Text('Explore first with a demo shop'),
                ),
              ),
              const SizedBox(height: 24),
              _ThemeDots(store: store),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  'Offline · your data stays on this computer',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: p.faint,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _people(SoraPalette p) {
    final shop = store.data.shop.name;
    final groups = <Role, List<Staff>>{
      Role.owner: store.data.staff.where((s) => s.role == Role.owner).toList(),
      Role.manager: store.data.staff
          .where((s) => s.role == Role.manager)
          .toList(),
      Role.cashier: store.data.staff
          .where((s) => s.role == Role.cashier)
          .toList(),
    };
    final panelHeight = math.min(720.0, MediaQuery.sizeOf(context).height - 72);
    final panelWidth = math.max(
      320.0,
      math.min(1000.0, MediaQuery.sizeOf(context).width - 56),
    );
    return SizedBox(
      width: panelWidth,
      height: math.max(420.0, panelHeight),
      child: GlassPanel(
        blur: 38,
        radius: 32,
        padding: EdgeInsets.zero,
        tint: p.isLight ? const Color(0xF2F8F9FC) : const Color(0xF20A0F16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: p.isLight
              ? [
                  Colors.white.withValues(alpha: 0.96),
                  Colors.white.withValues(alpha: 0.80),
                ]
              : [
                  const Color(0xFF1B2432).withValues(alpha: 0.90),
                  const Color(0xFF070B11).withValues(alpha: 0.97),
                ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 860;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide)
                  Container(
                    width: 360,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          p.accent.withValues(alpha: 0.14),
                          p.accent.withValues(alpha: 0.035),
                          Colors.transparent,
                        ],
                      ),
                      border: Border(right: BorderSide(color: p.hairline)),
                    ),
                    padding: const EdgeInsets.fromLTRB(34, 40, 34, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ThemedMark(palette: p, size: 76),
                        const SizedBox(height: 28),
                        Text(
                          shop,
                          style: TextStyle(
                            fontSize: 29,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.9,
                            color: p.text,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'A calm place to sell.',
                          style: TextStyle(
                            fontSize: 13,
                            color: p.muted,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SoraSignature(palette: p, height: 16),
                        const Spacer(),
                        Text('THEME', style: overlineStyle(p)),
                        const SizedBox(height: 12),
                        _ThemeDots(store: store, wrap: true),
                        const SizedBox(height: 24),
                        Text(
                          'Sora PoS · v0.2\nOffline, private, yours.',
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.55,
                            color: p.faint,
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(38, 40, 38, 34),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(
                              'WELCOME BACK',
                              style: overlineStyle(p, color: p.accent),
                            ),
                            const Spacer(),
                            if (store.data.settings.demo)
                              const StatusPill(
                                label: 'DEMO',
                                icon: Icons.auto_awesome_rounded,
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Who’s on the till?',
                          style: TextStyle(
                            fontSize: 31,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                            color: p.text,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          'Everyone signs in with their own password. Every sale keeps the right name.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.5,
                            color: p.muted,
                          ),
                        ),
                        const SizedBox(height: 26),
                        for (final role in [
                          Role.owner,
                          Role.manager,
                          Role.cashier,
                        ])
                          if (groups[role]!.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 2,
                                bottom: 9,
                                top: 4,
                              ),
                              child: Text(
                                role == Role.owner
                                    ? 'OWNER'
                                    : role == Role.manager
                                    ? 'MANAGERS'
                                    : 'CASHIERS',
                                style: overlineStyle(p),
                              ),
                            ),
                            for (final s in groups[role]!) ...[
                              _PersonTile(
                                staff: s,
                                palette: p,
                                onTap: () => _askPassword(s),
                              ),
                              const SizedBox(height: 9),
                            ],
                            const SizedBox(height: 12),
                          ],
                        const SizedBox(height: 6),
                        Text(
                          store.data.settings.demo ? 'Demo password: demo1234' : 'A forgotten password can be reset by another owner in Setup → Staff & access.',
                          style: TextStyle(
                            fontSize: 11,
                            color: p.faint,
                            height: 1.4,
                          ),
                        ),
                        if (!wide) ...[
                          const SizedBox(height: 26),
                          _ThemeDots(store: store),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _askPassword(Staff staff) {
    showSoraDialog<void>(
      context,
      maxWidth: 430,
      builder: (context) => _PasswordDialog(store: store, staff: staff),
    );
  }
}

class _PersonTile extends StatefulWidget {
  final Staff staff;
  final SoraPalette palette;
  final VoidCallback onTap;
  const _PersonTile({
    required this.staff,
    required this.palette,
    required this.onTap,
  });

  @override
  State<_PersonTile> createState() => _PersonTileState();
}

class _PersonTileState extends State<_PersonTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
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
          duration: const Duration(milliseconds: 170),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: _hover ? p.accent.withValues(alpha: 0.075) : p.raised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hover ? p.accent.withValues(alpha: 0.36) : p.hairline,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      p.accent.withValues(alpha: 0.28),
                      p.accent.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: p.accent.withValues(alpha: 0.24)),
                ),
                child: Text(
                  s.initials,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: p.accent,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: p.text,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.role.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: roleColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSlide(
                offset: _hover ? Offset.zero : const Offset(-0.15, 0),
                duration: const Duration(milliseconds: 170),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 17,
                  color: _hover ? p.accent : p.faint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  final Store store;
  final Staff staff;
  const _PasswordDialog({required this.store, required this.staff});

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final result = widget.store.signIn(widget.staff.id, _controller.text);
    if (result == null) {
      setState(() => _error = 'That password was not recognised.');
      _focus.requestFocus();
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final first = widget.staff.name.split(' ').first;
    return SoraDialog(
      title: 'Hello, $first',
      subtitle: '${widget.staff.role.label} · ${widget.store.data.shop.name}',
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
            label: 'Your password',
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
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: p.faint),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Signing in keeps your name on every sale, refund and void.',
                  style: TextStyle(fontSize: 11, color: p.faint, height: 1.4),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        GlassButton(
          label: 'Not me',
          onPressed: () => Navigator.of(context).pop(),
        ),
        GlassButton(
          label: 'Sign in',
          icon: Icons.arrow_forward_rounded,
          primary: true,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _ThemeDots extends StatelessWidget {
  final Store store;
  final bool wrap;
  const _ThemeDots({required this.store, this.wrap = false});

  @override
  Widget build(BuildContext context) {
    final current = store.data.appearance.themeId;
    final p = context.palette;
    final dots = <Widget>[];
    for (final theme in SoraPalette.named) {
      final selected = current == theme.id;
      dots.add(
        Tooltip(
          message: theme.name,
          child: GestureDetector(
            onTapUp: (details) =>
                pickTheme(store, theme.id, details.globalPosition),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: selected ? 22 : 17,
              height: selected ? 22 : 17,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [theme.accent, theme.accent2]),
                border: Border.all(
                  color: selected ? p.text.withValues(alpha: 0.85) : p.hairline,
                  width: selected ? 2 : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: theme.accent.withValues(alpha: 0.45),
                          blurRadius: 12,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      );
    }
    return Wrap(spacing: 9, runSpacing: 9, children: dots);
  }
}
