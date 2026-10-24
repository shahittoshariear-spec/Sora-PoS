import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../models.dart';
import '../services/native.dart';
import '../services/paths.dart';
import '../services/receipts.dart';
import '../store.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import '../ui/theme_switcher.dart';

class SetupScreen extends StatefulWidget {
  final Store store;
  const SetupScreen({super.key, required this.store});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int _pane = _paneFromEnvironment();

  static int _paneFromEnvironment() {
    final raw = Platform.environment['SORA_START_PANE'];
    if (raw == null || raw.trim().isEmpty) return 0;
    final names = [
      'shop',
      'receipt',
      'staff',
      'categories',
      'backups',
      'import',
      'shortcuts',
      'appearance',
      'email',
      'danger',
    ];
    final byName = names.indexOf(raw.trim().toLowerCase());
    if (byName != -1) return byName;
    final number = int.tryParse(raw.trim());
    if (number != null && number >= 0 && number < names.length) return number;
    return 0;
  }

  Store get store => widget.store;

  static const _panes = <(String, IconData)>[
    ('Shop', Icons.storefront_rounded),
    ('Receipt', Icons.print_rounded),
    ('Staff', Icons.badge_outlined),
    ('Categories', Icons.category_outlined),
    ('Backups', Icons.cloud_sync_outlined),
    ('Import', Icons.file_upload_outlined),
    ('Shortcuts', Icons.keyboard_rounded),
    ('Appearance', Icons.palette_outlined),
    ('Email', Icons.mail_outline_rounded),
    ('Danger zone', Icons.warning_amber_rounded),
  ];

  Widget _content() {
    switch (_pane) {
      case 1:
        return _ReceiptPane(key: const ValueKey('receipt'), store: store);
      case 2:
        return _StaffPane(key: const ValueKey('staff'), store: store);
      case 3:
        return _CategoriesPane(key: const ValueKey('categories'), store: store);
      case 4:
        return _BackupsPane(key: const ValueKey('backups'), store: store);
      case 5:
        return _ImportPane(key: const ValueKey('import'), store: store);
      case 6:
        return _ShortcutsPane(key: const ValueKey('shortcuts'), store: store);
      case 7:
        return _AppearancePane(key: const ValueKey('appearance'), store: store);
      case 8:
        return _EmailPane(key: const ValueKey('email'), store: store);
      case 9:
        return _DangerPane(key: const ValueKey('danger'), store: store);
      default:
        return _ShopPane(key: const ValueKey('shop'), store: store);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 206,
          child: GlassPanel(
            blur: 22,
            radius: 20,
            padding: const EdgeInsets.all(9),
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 10),
                  child: Text('SETUP', style: overlineStyle(p)),
                ),
                for (var i = 0; i < _panes.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: _SetupTab(
                      label: _panes[i].$1,
                      icon: _panes[i].$2,
                      selected: _pane == i,
                      danger: i == 9,
                      onTap: () => setState(() => _pane = i),
                    ),
                  ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'Changes apply the moment they are saved.',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: p.faint,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GlassPanel(
            blur: 24,
            radius: 20,
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(26, 24, 26, 26),
              child: _content(),
            ),
          ),
        ),
      ],
    );
  }
}

class _SetupTab extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool danger;
  final VoidCallback onTap;
  const _SetupTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.danger,
    required this.onTap,
  });

  @override
  State<_SetupTab> createState() => _SetupTabState();
}

class _SetupTabState extends State<_SetupTab> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final onAccent = p.accent.computeLuminance() > 0.47
        ? const Color(0xFF08120F)
        : Colors.white;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            gradient: widget.selected
                ? LinearGradient(
                    colors: widget.danger
                        ? [
                            p.danger.withValues(alpha: 0.22),
                            p.danger.withValues(alpha: 0.07),
                          ]
                        : [
                            p.accent.withValues(alpha: 0.22),
                            p.accent.withValues(alpha: 0.07),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: widget.selected
                ? null
                : (_hover ? p.raised : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
            border: widget.selected
                ? Border.all(
                    color: (widget.danger ? p.danger : p.accent).withValues(
                      alpha: 0.26,
                    ),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: widget.selected
                    ? (widget.danger ? p.danger : p.accent)
                    : (widget.danger ? p.danger : p.muted),
              ),
              const SizedBox(width: 9),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: widget.selected
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: widget.selected
                      ? (widget.danger ? p.danger : p.accent)
                      : (widget.danger ? p.danger : p.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------- shop

class _ShopPane extends StatefulWidget {
  final Store store;
  const _ShopPane({super.key, required this.store});
  @override
  State<_ShopPane> createState() => _ShopPaneState();
}

class _ShopPaneState extends State<_ShopPane> {
  late final _name = TextEditingController(text: widget.store.data.shop.name);
  late final _address = TextEditingController(
    text: widget.store.data.shop.address,
  );
  late final _phone = TextEditingController(text: widget.store.data.shop.phone);
  late final _currency = TextEditingController(
    text: widget.store.data.shop.currency,
  );
  late final _tax = TextEditingController(
    text: numText(widget.store.data.shop.taxRate),
  );
  late final _low = TextEditingController(
    text: numText(widget.store.data.shop.lowStock),
  );
  late final _footer = TextEditingController(
    text: widget.store.data.shop.receiptFooter,
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    _currency.dispose();
    _tax.dispose();
    _low.dispose();
    _footer.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'The shop needs a name.');
      return;
    }
    final tax = double.tryParse(_tax.text.replaceAll(',', '.'));
    final low = double.tryParse(_low.text.replaceAll(',', '.'));
    if (tax == null || tax < 0 || tax > 100) {
      setState(() => _error = 'The tax rate must be between 0 and 100.');
      return;
    }
    if (low == null || low < 0) {
      setState(() => _error = 'The low-stock threshold must be a number.');
      return;
    }
    final shop = widget.store.data.shop
      ..name = name
      ..address = _address.text.trim()
      ..phone = _phone.text.trim()
      ..currency = _currency.text.trim().isEmpty ? 'R' : _currency.text.trim()
      ..taxRate = tax
      ..lowStock = low
      ..receiptFooter = _footer.text.trim();
    setState(() => _error = null);
    widget.store.changed();
    await widget.store.saveNow();
    if (mounted) showToast(context, 'Shop details saved');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _Pane(
      title: 'Your shop',
      subtitle: 'These details appear on every receipt and on the day report.',
      children: [
        SoraField(
          controller: _name,
          label: 'Shop name',
          icon: Icons.storefront_rounded,
        ),
        const SizedBox(height: 13),
        SoraField(
          controller: _address,
          label: 'Address',
          hint: 'Street, suburb, city',
          icon: Icons.place_outlined,
          maxLines: 3,
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            Expanded(
              child: SoraField(
                controller: _phone,
                label: 'Phone',
                icon: Icons.phone_outlined,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: SoraField(
                controller: _currency,
                label: 'Currency',
                icon: Icons.payments_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            Expanded(
              child: SoraField(
                controller: _tax,
                label: 'Tax rate (%)',
                icon: Icons.percent_rounded,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SoraField(
                controller: _low,
                label: 'Low-stock threshold',
                icon: Icons.warning_amber_rounded,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        SoraField(
          controller: _footer,
          label: 'Receipt footer',
          icon: Icons.notes_rounded,
          maxLines: 2,
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(fontSize: 12, color: p.danger)),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            GlassButton(
              label: 'Save shop details',
              icon: Icons.check_rounded,
              primary: true,
              onPressed: _save,
            ),
            const Spacer(),
            Text(
              'Stored on this computer only',
              style: TextStyle(fontSize: 10.5, color: p.faint),
            ),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ receipt

class _ReceiptPane extends StatefulWidget {
  final Store store;
  const _ReceiptPane({super.key, required this.store});
  @override
  State<_ReceiptPane> createState() => _ReceiptPaneState();
}

class _ReceiptPaneState extends State<_ReceiptPane> {
  List<String> _printers = [];
  String _printer = '';
  bool _loading = true;
  bool _testing = false;

  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    _printer = store.data.settings.receiptPrinter;
    NativeCore.printers().then((list) {
      if (!mounted) return;
      setState(() {
        _printers = list;
        _loading = false;
      });
    });
  }

  Future<void> _test() async {
    if (_printer.isEmpty) {
      showToast(context, 'Choose a printer first.');
      return;
    }
    setState(() => _testing = true);
    try {
      await NativeCore.printRaw(
        _printer,
        escPosBytes(
          testReceiptText(store, printer: _printer),
          cut: store.data.settings.cutPaper,
        ),
      );
      if (mounted) showToast(context, 'Test receipt sent');
    } catch (e) {
      if (mounted)
        showToast(context, 'The printer did not take it. $e', error: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _Pane(
      title: 'Receipt printer',
      subtitle: 'Sora talks to thermal printers directly, in ESC/POS, 32 columns wide.',
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          SoraSelect<String>(
            label: 'Where receipts go',
            value: _printer,
            icon: Icons.print_rounded,
            options: [
              const SoraSelectOption('', 'Ask me each time'),
              for (final printer in _printers)
                SoraSelectOption(printer, printer),
            ],
            onChanged: (v) async {
              setState(() => _printer = v);
              store.data.settings.receiptPrinter = v;
              store.changed();
            },
          ),
        if (!_loading && _printers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Windows has no printers installed. Receipts stay on screen and can be saved as PDFs.',
              style: TextStyle(fontSize: 11, color: p.warning),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            GlassButton(
              label: 'Test print',
              icon: Icons.print_rounded,
              loading: _testing,
              onPressed: _printers.isEmpty ? null : _test,
            ),
            const SizedBox(width: 9),
            Text(
              _printer.isEmpty
                  ? 'Choose a printer to test it.'
                  : 'A short test goes to $_printer.',
              style: TextStyle(fontSize: 10.5, color: p.faint),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SwitchRow(
          title: 'Cut the paper after each receipt',
          subtitle: 'Only turn this on once a cut has worked on your printer. A printer that refuses a cut can refuse the next receipt too.',
          value: store.data.settings.cutPaper,
          onChanged: (v) {
            store.data.settings.cutPaper = v;
            store.changed();
          },
        ),
        const SizedBox(height: 14),
        SwitchRow(
          title: 'A chime when a sale lands',
          subtitle: 'A soft water-drop ring as the receipt appears. The sale is never held up by the sound.',
          value: store.data.settings.chime,
          onChanged: (v) {
            store.data.settings.chime = v;
            store.changed();
          },
        ),
        const SizedBox(height: 20),
        _Note(
          icon: Icons.info_outline_rounded,
          text:
              'Receipts print with plain text and a limited accent table. Anything outside it prints as “?”. '
              'Leave the printer on “Ask me each time” to keep the Windows print dialog, or to save a receipt as a PDF.',
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- staff

class _StaffPane extends StatefulWidget {
  final Store store;
  const _StaffPane({super.key, required this.store});
  @override
  State<_StaffPane> createState() => _StaffPaneState();
}

class _StaffPaneState extends State<_StaffPane> {
  Store get store => widget.store;

  Future<void> _edit([Staff? person]) async {
    await showSoraDialog<void>(
      context,
      maxWidth: 500,
      builder: (context) => _StaffDialog(store: store, staff: person),
    );
    if (mounted) setState(() {});
  }

  Future<void> _delete(Staff person) async {
    final p = context.palette;
    final confirmed = await showSoraDialog<bool>(
      context,
      maxWidth: 430,
      builder: (context) => SoraDialog(
        title: 'Remove ${person.name}?',
        subtitle: 'Their past sales keep their name. They simply cannot sign in again.',
        icon: Icons.person_remove_outlined,
        accent: p.danger,
        child: const SizedBox.shrink(),
        actions: [
          GlassButton(
            label: 'Keep them',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          GlassButton(
            label: 'Remove',
            danger: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await store.deleteStaff(person.id);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _Pane(
      title: 'Staff & access',
      subtitle: 'Every sale, refund and void keeps the name of the person who did it.',
      trailing: GlassButton(
        label: 'Add someone',
        icon: Icons.person_add_alt_rounded,
        primary: true,
        dense: true,
        onPressed: () => _edit(),
      ),
      children: [
        for (final person in store.data.staff)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              decoration: BoxDecoration(
                color: p.raised,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: p.hairline),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: p.accent.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      person.initials,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: p.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          person.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: p.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          person.role == Role.owner
                              ? 'Owner · everything'
                              : person.role == Role.manager
                              ? 'Manager · stock, ledger, refunds'
                              : 'Cashier · the till',
                          style: TextStyle(fontSize: 10.5, color: p.faint),
                        ),
                      ],
                    ),
                  ),
                  StatusPill(
                    label: person.needsPassword
                        ? 'RESET PASSWORD'
                        : person.role.label.toUpperCase(),
                    color: person.needsPassword
                        ? p.warning
                        : person.role == Role.owner
                        ? p.accent
                        : person.role == Role.manager
                        ? p.accent2
                        : p.muted,
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: () => _edit(person),
                    icon: Icon(Icons.edit_outlined, size: 16, color: p.muted),
                    splashRadius: 18,
                  ),
                  IconButton(
                    onPressed: () => _delete(person),
                    icon: Icon(
                      Icons.person_remove_outlined,
                      size: 16,
                      color: p.faint,
                    ),
                    splashRadius: 18,
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        _Note(
          icon: Icons.lock_outline_rounded,
          text:
              'The last owner cannot be removed or demoted. Passwords are one-way hashes — nobody, including you, can read them back. '
              'If someone forgets theirs, another owner can set a new one here.',
        ),
      ],
    );
  }
}

class _StaffDialog extends StatefulWidget {
  final Store store;
  final Staff? staff;
  const _StaffDialog({required this.store, this.staff});
  @override
  State<_StaffDialog> createState() => _StaffDialogState();
}

class _StaffDialogState extends State<_StaffDialog> {
  late final _name = TextEditingController(text: widget.staff?.name ?? '');
  final _password = TextEditingController();
  late Role _role = widget.staff?.role ?? Role.cashier;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.staff == null) {
        await widget.store.addStaff(
          name: _name.text,
          password: _password.text,
          role: _role,
        );
      } else {
        if (widget.staff!.needsPassword && _password.text.isEmpty) {
          throw StoreException(
            'This imported account needs a password before it can sign in.',
          );
        }
        await widget.store.updateStaff(
          widget.staff!.id,
          name: _name.text,
          role: _role,
          password: _password.text.isEmpty ? null : _password.text,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.staff != null;
    final needsPassword = widget.staff?.needsPassword ?? false;
    return SoraDialog(
      title: editing ? 'Edit ${widget.staff!.name}' : 'Add someone',
      subtitle: editing
          ? (needsPassword
                ? 'This imported account needs a password before it can sign in.'
                : 'Leave the password empty to keep it as it is.')
          : 'They sign in with their own password.',
      icon: Icons.badge_outlined,
      width: 500,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SoraField(
            controller: _name,
            autofocus: true,
            label: 'Name',
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 13),
          SoraSelect<Role>(
            label: 'Title',
            value: _role,
            icon: Icons.workspace_premium_outlined,
            options: const [
              SoraSelectOption(Role.cashier, 'Cashier — the till'),
              SoraSelectOption(
                Role.manager,
                'Manager — stock, ledger, refunds',
              ),
              SoraSelectOption(Role.owner, 'Owner — everything'),
            ],
            onChanged: (v) => setState(() => _role = v),
          ),
          const SizedBox(height: 13),
          SoraField(
            controller: _password,
            label: editing
                ? (needsPassword ? 'New password' : 'New password (optional)')
                : 'Password',
            hint: 'At least four characters',
            icon: Icons.key_rounded,
            obscure: true,
            onSubmitted: (_) => _save(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(fontSize: 12, color: context.palette.danger),
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
          label: editing ? 'Save' : 'Add',
          icon: Icons.check_rounded,
          primary: true,
          loading: _busy,
          onPressed: _save,
        ),
      ],
    );
  }
}

// --------------------------------------------------------------- categories

class _CategoriesPane extends StatefulWidget {
  final Store store;
  const _CategoriesPane({super.key, required this.store});
  @override
  State<_CategoriesPane> createState() => _CategoriesPaneState();
}

class _CategoriesPaneState extends State<_CategoriesPane> {
  final _name = TextEditingController();

  Store get store => widget.store;

  int _count(String id) =>
      store.data.products.where((p) => p.categoryId == id).length;

  Future<void> _add() async {
    try {
      await store.addCategory(_name.text);
      _name.clear();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  Future<void> _rename(Category category) async {
    final controller = TextEditingController(text: category.name);
    final result = await showSoraDialog<String>(
      context,
      maxWidth: 420,
      builder: (context) => SoraDialog(
        title: 'Rename category',
        icon: Icons.edit_outlined,
        child: SoraField(
          controller: controller,
          autofocus: true,
          label: 'Name',
          onSubmitted: (_) => Navigator.of(context).pop(controller.text),
        ),
        actions: [
          GlassButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
          GlassButton(
            label: 'Save',
            primary: true,
            onPressed: () => Navigator.of(context).pop(controller.text),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    try {
      await store.renameCategory(category.id, result);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  Future<void> _delete(Category category) async {
    final p = context.palette;
    final others = store.data.categories
        .where((c) => c.id != category.id)
        .toList();
    if (others.isEmpty) {
      showToast(context, 'The last category cannot be removed.', error: true);
      return;
    }
    final count = _count(category.id);
    String moveTo = others.first.id;
    final confirmed = await showSoraDialog<bool>(
      context,
      maxWidth: 440,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => SoraDialog(
          title: 'Delete ${category.name}?',
          subtitle: count == 0
              ? 'Nothing is filed here.'
              : '$count ${plural(count, 'product')} are filed here. Where should they go?',
          icon: Icons.delete_outline_rounded,
          accent: p.danger,
          child: count == 0
              ? const SizedBox.shrink()
              : SoraSelect<String>(
                  label: 'Move them to',
                  value: moveTo,
                  options: others
                      .map((c) => SoraSelectOption(c.id, c.name))
                      .toList(),
                  onChanged: (v) => setLocal(() => moveTo = v),
                ),
          actions: [
            GlassButton(
              label: 'Keep it',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            GlassButton(
              label: 'Delete',
              danger: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await store.deleteCategory(category.id, moveTo: moveTo);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _Pane(
      title: 'Categories',
      subtitle: 'A product belongs to one category. Deleting a category never loses a product.',
      children: [
        Row(
          children: [
            Expanded(
              child: SoraField(
                controller: _name,
                label: 'New category',
                hint: 'e.g. Bakery',
                icon: Icons.add_rounded,
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 23),
              child: GlassButton(
                label: 'Add',
                icon: Icons.add_rounded,
                primary: true,
                onPressed: _add,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (final category in store.data.categories)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              decoration: BoxDecoration(
                color: p.raised,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: p.hairline),
              ),
              child: Row(
                children: [
                  Icon(Icons.folder_outlined, size: 16, color: p.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      category.name,
                      style: TextStyle(fontSize: 12.5, color: p.text),
                    ),
                  ),
                  Text(
                    '${_count(category.id)} ${plural(_count(category.id), 'product')}',
                    style: TextStyle(fontSize: 10.5, color: p.faint),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () => _rename(category),
                    icon: Icon(Icons.edit_outlined, size: 15, color: p.muted),
                    splashRadius: 17,
                  ),
                  IconButton(
                    onPressed: () => _delete(category),
                    icon: Icon(Icons.close_rounded, size: 15, color: p.faint),
                    splashRadius: 17,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------------ backups

class _BackupsPane extends StatefulWidget {
  final Store store;
  const _BackupsPane({super.key, required this.store});
  @override
  State<_BackupsPane> createState() => _BackupsPaneState();
}

class _BackupsPaneState extends State<_BackupsPane> {
  bool _busy = false;

  Store get store => widget.store;

  Future<void> _backupNow() async {
    setState(() => _busy = true);
    final file = await store.backupNow();
    if (!mounted) return;
    setState(() => _busy = false);
    showToast(
      context,
      file == null
          ? 'The backup could not be written.'
          : 'Backup taken · ${file.path.split(Platform.pathSeparator).last}',
      error: file == null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final backups = store.listBackups();
    final last = store.lastBackupAt;
    return _Pane(
      title: 'Backups',
      subtitle: 'A copy of the shop’s data file lives beside it. The newest twelve are kept.',
      children: [
        SwitchRow(
          title: 'Automatic backups',
          subtitle: 'Taken while the app is open.',
          value: store.data.settings.autoBackups,
          onChanged: (v) {
            store.data.settings.autoBackups = v;
            store.changed();
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 230,
              child: SoraSelect<String>(
                label: 'How often',
                value: store.data.settings.backupFrequency,
                options: const [
                  SoraSelectOption('daily', 'Every day'),
                  SoraSelectOption('weekly', 'Every week'),
                  SoraSelectOption('monthly', 'Every month'),
                  SoraSelectOption('off', 'Off'),
                ],
                onChanged: (v) {
                  store.data.settings.backupFrequency = v;
                  store.changed();
                },
              ),
            ),
            const Spacer(),
            GlassButton(
              label: 'Back up now',
              icon: Icons.save_outlined,
              primary: true,
              loading: _busy,
              onPressed: _backupNow,
            ),
            const SizedBox(width: 8),
            GlassButton(
              label: 'Export…',
              icon: Icons.ios_share_rounded,
              dense: true,
              onPressed: _export,
            ),
            const SizedBox(width: 8),
            GlassButton(
              label: 'Import…',
              icon: Icons.download_rounded,
              dense: true,
              onPressed: _import,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Icon(Icons.folder_outlined, size: 15, color: p.faint),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                store.rootDir.path,
                style: TextStyle(
                  fontSize: 10.5,
                  color: p.faint,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ),
            TextButton(
              onPressed: () => NativeCore.openFile(store.rootDir.path),
              child: const Text('Open folder', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          last == null
              ? 'No backup has been taken yet.'
              : 'Newest backup: ${dateMedium(last)} at ${timeShort(last)}',
          style: TextStyle(fontSize: 11, color: p.muted),
        ),
        const SizedBox(height: 14),
        if (backups.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: p.raised,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              children: [
                for (var i = 0; i < backups.length && i < 12; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 14,
                          color: p.faint,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            backups[i].path.split(Platform.pathSeparator).last,
                            style: TextStyle(
                              fontSize: 11,
                              color: p.muted,
                              fontFamily: 'JetBrains Mono',
                            ),
                          ),
                        ),
                        Text(
                          '${(backups[i].lengthSync() / 1024).toStringAsFixed(0)} KB',
                          style: TextStyle(fontSize: 10, color: p.faint),
                        ),
                        if (i < backups.length - 1 && i < 11)
                          const SizedBox.shrink(),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        _Note(
          icon: Icons.shield_outlined,
          text:
              'Both danger-zone resets take a backup first, and refuse to go ahead if that copy cannot be written. '
              'Importing a backup also keeps a safety copy of what is open now.',
        ),
      ],
    );
  }

  Future<void> _export() async {
    try {
      final path = await store.exportBackup();
      if (path != null && mounted) showToast(context, 'Exported to $path');
    } catch (e) {
      if (mounted) showToast(context, 'Could not export. $e', error: true);
    }
  }

  Future<void> _import() async {
    try {
      final path = await store.importBackup();
      if (path != null && mounted)
        showToast(context, 'Backup restored. Sign in again.');
    } catch (e) {
      if (mounted) showToast(context, 'Could not restore. $e', error: true);
    }
  }
}

// ------------------------------------------------------------------- import

class _ImportPane extends StatefulWidget {
  final Store store;
  const _ImportPane({super.key, required this.store});
  @override
  State<_ImportPane> createState() => _ImportPaneState();
}

class _ImportPaneState extends State<_ImportPane> {
  String? _path;
  ImportPreview? _preview;
  List<int> _mapping = [-1, -1, -1, -1, -1, -1];
  bool _loading = false;
  bool _importing = false;

  Store get store => widget.store;

  static const _fields = <(String, String)>[
    ('name', 'Name'),
    ('sku', 'SKU / barcode'),
    ('category', 'Category'),
    ('price', 'Sell price'),
    ('cost', 'Cost'),
    ('stock', 'Stock'),
  ];

  Future<void> _choose() async {
    try {
      final path = await NativeCore.openDialog(
        title: 'Import a product list',
        filter: 'Spreadsheets|*.xlsx;*.xls;*.xlsb;*.ods;*.csv|All files|*.*',
      );
      if (path == null) return;
      setState(() => _loading = true);
      final preview = await NativeCore.readSpreadsheet(path);
      if (!mounted) return;
      setState(() {
        _path = path;
        _preview = preview;
        _mapping = [
          preview.mapping['name'] ?? -1,
          preview.mapping['sku'] ?? -1,
          preview.mapping['category'] ?? -1,
          preview.mapping['price'] ?? -1,
          preview.mapping['cost'] ?? -1,
          preview.mapping['stock'] ?? -1,
        ];
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showToast(context, e.toString(), error: true);
      }
    }
  }

  Future<void> _import() async {
    if (_path == null || _preview == null) return;
    if (_mapping[0] < 0) {
      showToast(context, 'Choose which column holds the product name.');
      return;
    }
    setState(() => _importing = true);
    try {
      final items = await NativeCore.readProducts(_path!, _mapping);
      final result = await store.applyImportedProducts(items);
      if (!mounted) return;
      setState(() {
        _importing = false;
        _preview = null;
        _path = null;
      });
      showToast(context, '${result.added} added, ${result.updated} updated.');
    } catch (e) {
      if (mounted) {
        setState(() => _importing = false);
        showToast(context, e.toString(), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final preview = _preview;
    return _Pane(
      title: 'Import products',
      subtitle: 'Bring a list from POS Maid, another till, or any spreadsheet.',
      children: [
        Row(
          children: [
            GlassButton(
              label: preview == null
                  ? 'Choose a spreadsheet…'
                  : 'Choose another…',
              icon: Icons.file_open_outlined,
              primary: preview == null,
              loading: _loading,
              onPressed: _choose,
            ),
            const SizedBox(width: 10),
            if (_path != null)
              Expanded(
                child: Text(
                  _path!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: p.faint,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
              ),
          ],
        ),
        if (preview == null) ...[
          const SizedBox(height: 16),
          _Note(
            icon: Icons.table_chart_outlined,
            text:
                'Excel (.xlsx, .xls, .xlsb), OpenDocument (.ods) and CSV are read. Sora guesses which column is which, and lets you correct it before anything is imported. '
                'A product with a matching SKU is updated; everything else is added. Categories are created as needed.',
          ),
        ] else ...[
          const SizedBox(height: 16),
          Row(
            children: [
              StatusPill(
                label: '${preview.totalRows} rows',
                color: p.accent,
                icon: Icons.table_rows_outlined,
              ),
              const SizedBox(width: 8),
              Text(
                'Sheet: ${preview.sheet}',
                style: TextStyle(fontSize: 11, color: p.muted),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SectionLabel('Match the columns'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < _fields.length; i++)
                SizedBox(
                  width: 166,
                  child: SoraSelect<int>(
                    label: _fields[i].$2,
                    value: _mapping[i],
                    dense: true,
                    options: [
                      const SoraSelectOption(-1, 'Not used'),
                      for (var c = 0; c < preview.headers.length; c++)
                        SoraSelectOption(c, preview.headers[c]),
                    ],
                    onChanged: (v) => setState(() => _mapping[i] = v),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SectionLabel('A look at the rows'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: p.raised,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: p.hairline),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 34,
                dataRowMinHeight: 30,
                dataRowMaxHeight: 34,
                columns: preview.headers
                    .take(7)
                    .map(
                      (h) => DataColumn(
                        label: Text(
                          h,
                          style: TextStyle(
                            fontSize: 10,
                            color: p.faint,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                rows: preview.rows
                    .take(6)
                    .map(
                      (row) => DataRow(
                        cells: List.generate(
                          preview.headers.take(7).length,
                          (i) => DataCell(
                            Text(
                              i < row.length ? row[i] : '',
                              style: TextStyle(fontSize: 10.5, color: p.text),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              GlassButton(
                label: 'Import products',
                icon: Icons.download_rounded,
                primary: true,
                loading: _importing,
                onPressed: _import,
              ),
              const SizedBox(width: 10),
              Text(
                'Existing SKUs are updated. New ones are added.',
                style: TextStyle(fontSize: 10.5, color: p.faint),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- shortcuts

class _ShortcutsPane extends StatefulWidget {
  final Store store;
  const _ShortcutsPane({super.key, required this.store});
  @override
  State<_ShortcutsPane> createState() => _ShortcutsPaneState();
}

class _ShortcutsPaneState extends State<_ShortcutsPane> {
  Store get store => widget.store;

  Future<void> _capture(ShortcutBinding binding) async {
    final result = await showSoraDialog<String>(
      context,
      maxWidth: 420,
      dismissible: false,
      builder: (context) => _KeyCaptureDialog(current: binding.keys),
    );
    if (result == null) return;
    binding.keys = result;
    store.changed();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bindings = shortcutActions
        .map((a) => store.data.shortcuts[a.id])
        .whereType<ShortcutBinding>()
        .toList();
    return _Pane(
      title: 'Keyboard shortcuts',
      subtitle: 'A function key, or anything with Ctrl or Alt — never something that could be typed by accident.',
      trailing: GlassButton(
        label: 'Reset to defaults',
        icon: Icons.restart_alt_rounded,
        dense: true,
        onPressed: () {
          store.data.shortcuts = defaultShortcuts();
          store.changed();
          setState(() {});
          showToast(context, 'Shortcuts are back to their defaults.');
        },
      ),
      children: [
        for (final action in shortcutActions) ...[
          if (action.group == 'Screens') const SizedBox.shrink(),
          Builder(
            builder: (context) {
              final binding = store.data.shortcuts[action.id]!;
              final hold = binding.hold;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(13, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: p.raised,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.hairline),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              action.label,
                              style: TextStyle(fontSize: 12, color: p.text),
                            ),
                            Text(
                              action.group.toUpperCase(),
                              style: TextStyle(
                                fontSize: 8.5,
                                color: p.faint,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Tooltip(
                        message: hold
                            ? 'Hold the key to fire'
                            : 'Fires on press',
                        child: GestureDetector(
                          onTap: () {
                            binding.hold = !binding.hold;
                            store.changed();
                            setState(() {});
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: hold
                                  ? p.accent.withValues(alpha: 0.12)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: hold
                                    ? p.accent.withValues(alpha: 0.3)
                                    : p.hairline,
                              ),
                            ),
                            child: Text(
                              hold ? 'On hold' : 'On press',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: hold ? p.accent : p.faint,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _capture(binding),
                        child: Container(
                          width: 92,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: p.night.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: p.hairline),
                          ),
                          child: Text(
                            binding.keys.isEmpty ? '—' : binding.keys,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontFamily: 'JetBrains Mono',
                              color: binding.keys.isEmpty ? p.faint : p.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: binding.keys.isEmpty
                            ? null
                            : () {
                                binding.keys = '';
                                store.changed();
                                setState(() {});
                              },
                        icon: Icon(
                          Icons.close_rounded,
                          size: 13,
                          color: p.faint,
                        ),
                        splashRadius: 15,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
        const SizedBox(height: 10),
        _Note(
          icon: Icons.info_outline_rounded,
          text:
              'Anything that throws work away can be set to “On hold”, so a brush against the keyboard cannot empty a sale. '
              'Function keys and combinations are the only ones accepted.',
        ),
      ],
    );
  }
}

class _KeyCaptureDialog extends StatefulWidget {
  final String current;
  const _KeyCaptureDialog({required this.current});
  @override
  State<_KeyCaptureDialog> createState() => _KeyCaptureDialogState();
}

class _KeyCaptureDialogState extends State<_KeyCaptureDialog> {
  String? _error;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final label = event.logicalKey.keyLabel;
    const modifiers = {'control', 'shift', 'alt', 'meta', 'caps lock', 'fn'};
    if (label.trim().isEmpty || modifiers.contains(label.toLowerCase()))
      return KeyEventResult.handled;
    final keyboard = HardwareKeyboard.instance;
    final hasModifier =
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed;
    final isFunction = RegExp(r'^F\d{1,2}$').hasMatch(label.toUpperCase());
    if (!hasModifier && !isFunction) {
      setState(() => _error = 'Use a function key, or hold Ctrl or Alt too.');
      return KeyEventResult.handled;
    }
    final parts = <String>[];
    if (keyboard.isControlPressed) parts.add('Ctrl');
    if (keyboard.isAltPressed) parts.add('Alt');
    if (keyboard.isShiftPressed) parts.add('Shift');
    if (keyboard.isMetaPressed) parts.add('Meta');
    parts.add(label.toUpperCase());
    Navigator.of(context).pop(parts.join('+'));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: SoraDialog(
        title: 'Press the new shortcut',
        subtitle: widget.current.isEmpty
            ? 'Nothing is bound yet.'
            : 'Now: ${widget.current}',
        icon: Icons.keyboard_rounded,
        showClose: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.accent.withValues(alpha: 0.16)),
              ),
              child: Text(
                'Press a function key, or hold Ctrl/Alt and press a key. Escape cancels.',
                style: TextStyle(fontSize: 11.5, color: p.muted, height: 1.5),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(fontSize: 11.5, color: p.danger)),
            ],
          ],
        ),
        actions: [
          GlassButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- appearance

class _AppearancePane extends StatefulWidget {
  final Store store;
  const _AppearancePane({super.key, required this.store});
  @override
  State<_AppearancePane> createState() => _AppearancePaneState();
}

class _AppearancePaneState extends State<_AppearancePane> {
  Store get store => widget.store;
  Appearance get appearance => store.data.appearance;

  Future<void> _editCustom(int index) async {
    final slot = appearance.customs[index];
    final result = await showSoraDialog<CustomTheme>(
      context,
      maxWidth: 560,
      builder: (context) => _CustomThemeDialog(theme: slot),
    );
    if (result == null) return;
    appearance.customs[index] = result;
    await pickTheme(store, 'custom$index', null);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _Pane(
      title: 'Appearance',
      subtitle: 'Nine marks, three of your own, nine typefaces, four sizes and two surface styles. Everything applies as it is picked.',
      children: [
        SectionLabel('THEME'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final theme in SoraPalette.named)
              _ThemeTile(
                theme: theme,
                selected: appearance.themeId == theme.id,
                onTap: (origin) {
                  pickTheme(store, theme.id, origin);
                  setState(() {});
                },
              ),
            for (var i = 0; i < 3; i++)
              _CustomTile(
                theme: appearance.customs[i],
                selected: appearance.themeId == 'custom$i',
                onTap: (origin) {
                  pickTheme(store, 'custom$i', origin);
                  setState(() {});
                },
                onEdit: () => _editCustom(i),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            SectionLabel('TYPEFACE'),
            const Spacer(),
            Text(
              'Screens use the first choice',
              style: TextStyle(fontSize: 9.5, color: p.faint),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: [
            for (var i = 0; i < fontChoices.length; i++)
              GestureDetector(
                onTap: () {
                  appearance.fontIndex = i;
                  store.changed();
                  setState(() {});
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 148,
                  height: 58,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: appearance.fontIndex == i
                        ? p.accent.withValues(alpha: 0.10)
                        : p.raised,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: appearance.fontIndex == i
                          ? p.accent.withValues(alpha: 0.5)
                          : p.hairline,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aa',
                        style: TextStyle(
                          fontFamily: fontChoices[i].family,
                          fontSize: 18,
                          color: p.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        fontChoices[i].family,
                        style: TextStyle(
                          fontFamily: fontChoices[i].family,
                          fontSize: 9.5,
                          color: p.faint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        SectionLabel('TEXT SIZE'),
        const SizedBox(height: 9),
        SizedBox(
          width: 420,
          child: SoraSegmented<int>(
            values: const [0, 1, 2, 3],
            selected: textSizes.indexOf(appearance.textScale) == -1
                ? 1
                : textSizes.indexOf(appearance.textScale),
            label: (v) => textSizeLabels[v],
            dense: true,
            onChanged: (v) {
              appearance.textScale = textSizes[v];
              store.changed();
              setState(() {});
            },
          ),
        ),
        const SizedBox(height: 24),
        SectionLabel('SURFACE'),
        const SizedBox(height: 9),
        SizedBox(
          width: 420,
          child: SoraSegmented<String>(
            values: const ['glass', 'matte'],
            selected: appearance.surfaceStyle,
            label: (v) => v == 'matte' ? 'Matte Flat' : 'Glass Blur',
            dense: true,
            onChanged: (v) {
              appearance.surfaceStyle = v;
              store.changed();
              setState(() {});
            },
          ),
        ),
        const SizedBox(height: 7),
        Text(
          appearance.surfaceStyle == 'matte'
              ? 'Opaque near-black panels, flat colour and no glow. The calm option for a bright room or a busy screen.'
              : 'Tinted glass over a still, soft aurora. The default Sora look.',
          style: TextStyle(fontSize: 10.5, color: p.faint),
        ),
        const SizedBox(height: 24),
        SectionLabel('NAVIGATION'),
        const SizedBox(height: 9),
        SizedBox(
          width: 360,
          child: SoraSegmented<bool>(
            values: const [false, true],
            selected: appearance.dockNav,
            label: (v) => v ? 'Floating dock' : 'Sidebar',
            dense: true,
            onChanged: (v) {
              appearance.dockNav = v;
              store.changed();
              setState(() {});
            },
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'The floating dock sits at the bottom of the window and gives the shop its full width.',
          style: TextStyle(fontSize: 10.5, color: p.faint),
        ),
        const SizedBox(height: 24),
        SectionLabel('WHERE THE SCREENS SIT'),
        const SizedBox(height: 9),
        SizedBox(
          width: 360,
          child: SoraSegmented<String>(
            values: const ['side', 'top'],
            selected: appearance.navPosition,
            label: (v) => v == 'side' ? 'Down the side' : 'Across the top',
            dense: true,
            onChanged: (v) {
              appearance.navPosition = v;
              store.changed();
              setState(() {});
            },
          ),
        ),
        const SizedBox(height: 24),
        _Note(
          icon: Icons.auto_awesome_rounded,
          text:
              'Sora follows Windows’ reduced-motion setting: turn that on and screens change instantly with no animation. '
              'The custom theme’s icon is hue-tinted from the shop’s teal mark; the taskbar uses the nearest matching icon. '
              'Side or top placement applies when the sidebar is chosen.',
        ),
      ],
    );
  }
}

class _ThemeTile extends StatefulWidget {
  final SoraPalette theme;
  final bool selected;
  final void Function(Offset? globalOrigin) onTap;
  const _ThemeTile({
    required this.theme,
    required this.selected,
    required this.onTap,
  });
  @override
  State<_ThemeTile> createState() => _ThemeTileState();
}

class _ThemeTileState extends State<_ThemeTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapUp: (details) => widget.onTap(details.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          width: 148,
          height: 74,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: widget.selected
                ? widget.theme.accent.withValues(alpha: 0.10)
                : p.raised,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: widget.selected
                  ? widget.theme.accent.withValues(alpha: 0.55)
                  : _hover
                  ? p.accent.withValues(alpha: 0.25)
                  : p.hairline,
            ),
          ),
          child: Row(
            children: [
              ThemedMark(palette: widget.theme, size: 44, shadow: false),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.theme.name,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: p.text,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        gradient: widget.theme.accentGradient,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomTile extends StatelessWidget {
  final CustomTheme theme;
  final bool selected;
  final void Function(Offset? globalOrigin) onTap;
  final VoidCallback onEdit;

  const _CustomTile({
    required this.theme,
    required this.selected,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final accent = Color(theme.accent);
    return GestureDetector(
      onTapUp: (details) => onTap(details.globalPosition),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        width: 148,
        height: 74,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.10) : p.raised,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.55) : p.hairline,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                gradient: LinearGradient(colors: [accent, Color(theme.night)]),
                border: Border.all(color: accent.withValues(alpha: 0.4)),
              ),
              child: IconButton(
                onPressed: onEdit,
                icon: Icon(
                  Icons.edit_outlined,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
                splashRadius: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    theme.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: p.text,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    selected ? 'Selected' : 'Your own',
                    style: TextStyle(
                      fontSize: 8.5,
                      color: selected ? accent : p.faint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomThemeDialog extends StatefulWidget {
  final CustomTheme theme;
  const _CustomThemeDialog({required this.theme});
  @override
  State<_CustomThemeDialog> createState() => _CustomThemeDialogState();
}

class _CustomThemeDialogState extends State<_CustomThemeDialog> {
  late final _name = TextEditingController(text: widget.theme.name);
  late Color _accent = Color(widget.theme.accent);
  late Color _night = Color(widget.theme.night);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick(bool accent) async {
    final picked = await showSoraDialog<Color>(
      context,
      maxWidth: 400,
      builder: (context) => _ColorPickerDialog(
        title: accent ? 'The accent' : 'The night',
        initial: accent ? _accent : _night,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (accent) {
        _accent = picked;
      } else {
        _night = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final preview = SoraPalette(
      id: 'preview',
      name: _name.text,
      night: _night,
      accent: _accent,
      accent2: Color.lerp(_accent, Colors.white, 0.4)!,
      iconAsset: SoraPalette.named.first.iconAsset,
      windowIcon: SoraPalette.named.first.windowIcon,
      custom: true,
      iconHueShift:
          HSLColor.fromColor(_accent).hue -
          HSLColor.fromColor(SoraPalette.named.first.accent).hue,
    );
    return SoraDialog(
      title: 'Make it yours',
      subtitle: 'An accent and a night. Everything else follows.',
      icon: Icons.palette_outlined,
      width: 540,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SoraField(
            controller: _name,
            label: 'Name',
            hint: 'e.g. Evening Fig',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ColorSlot(
                  label: 'ACCENT',
                  color: _accent,
                  onTap: () => _pick(true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ColorSlot(
                  label: 'NIGHT',
                  color: _night,
                  onTap: () => _pick(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            height: 74,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              gradient: preview.nightGradient,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              children: [
                ThemedMark(palette: preview, size: 40, shadow: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name.text.isEmpty ? 'Your theme' : _name.text,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: preview.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: 4,
                        width: 110,
                        decoration: BoxDecoration(
                          gradient: preview.accentGradient,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        GlassButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        GlassButton(
          label: 'Use this theme',
          icon: Icons.check_rounded,
          primary: true,
          onPressed: () => Navigator.of(context).pop(
            CustomTheme(
              name: _name.text.trim().isEmpty ? 'My theme' : _name.text.trim(),
              accent: _accent.toARGB32(),
              night: _night.toARGB32(),
            ),
          ),
        ),
      ],
    );
  }
}

class _ColorSlot extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ColorSlot({
    required this.label,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: p.raised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 8.5,
                      letterSpacing: 1,
                      color: p.faint,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: p.muted,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorPickerDialog extends StatefulWidget {
  final String title;
  final Color initial;
  const _ColorPickerDialog({required this.title, required this.initial});
  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  void _setSv(Offset position, Size size) {
    final s = (position.dx / size.width).clamp(0.0, 1.0);
    final v = 1 - (position.dy / size.height).clamp(0.0, 1.0);
    setState(() => _hsv = _hsv.withSaturation(s).withValue(v));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SoraDialog(
      title: widget.title,
      subtitle: 'Drag inside the square, then choose a hue.',
      icon: Icons.colorize_rounded,
      width: 400,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1.9,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return MouseRegion(
                  cursor: SystemMouseCursors.precise,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) => _setSv(event.localPosition, size),
                    onPointerMove: (event) => _setSv(event.localPosition, size),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(painter: _SvPainter(_hsv)),
                          ),
                          Positioned(
                            left: (_hsv.saturation * size.width - 7.5).clamp(
                              0.0,
                              size.width - 15,
                            ),
                            top: ((1 - _hsv.value) * size.height - 7.5).clamp(
                              0.0,
                              size.height - 15,
                            ),
                            child: IgnorePointer(
                              child: Container(
                                width: 15,
                                height: 15,
                                decoration: BoxDecoration(
                                  color: _hsv.toColor(),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black38,
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 26,
            child: LayoutBuilder(
              builder: (context, constraints) => MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) => setState(
                    () => _hsv = _hsv.withHue(
                      (event.localPosition.dx / constraints.maxWidth * 360)
                          .clamp(0, 359),
                    ),
                  ),
                  onPointerMove: (event) => setState(
                    () => _hsv = _hsv.withHue(
                      (event.localPosition.dx / constraints.maxWidth * 360)
                          .clamp(0, 359),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: CustomPaint(painter: _HuePainter()),
                        ),
                      ),
                      Positioned(
                        left: (_hsv.hue / 360) * constraints.maxWidth - 6,
                        top: 2,
                        child: IgnorePointer(
                          child: Container(
                            width: 12,
                            height: 22,
                            decoration: BoxDecoration(
                              color: _hsv.toColor(),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(color: Colors.black38, blurRadius: 5),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _hsv.toColor(),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.hairline),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '#${_hsv.toColor().toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                style: TextStyle(
                  fontSize: 12,
                  color: p.muted,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
              const Spacer(),
              Text(
                'S ${(_hsv.saturation * 100).round()}%  ·  V ${(_hsv.value * 100).round()}%',
                style: TextStyle(fontSize: 10, color: p.faint),
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
        GlassButton(
          label: 'Choose',
          icon: Icons.check_rounded,
          primary: true,
          onPressed: () => Navigator.of(context).pop(_hsv.toColor()),
        ),
      ],
    );
  }
}

class _SvPainter extends CustomPainter {
  final HSVColor hsv;
  _SvPainter(this.hsv);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hue = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    canvas.drawRect(rect, Paint()..color = hue);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Colors.white, Color(0x00FFFFFF)],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Colors.black],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _SvPainter old) => old.hsv != hsv;
}

class _HuePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final colors = [
      for (var i = 0; i <= 6; i++)
        HSVColor.fromAHSV(1, (i * 60) % 360, 1, 1).toColor(),
    ];
    canvas.drawRect(
      rect,
      Paint()..shader = LinearGradient(colors: colors).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// -------------------------------------------------------------------- email

class _EmailPane extends StatefulWidget {
  final Store store;
  const _EmailPane({super.key, required this.store});
  @override
  State<_EmailPane> createState() => _EmailPaneState();
}

class _EmailPaneState extends State<_EmailPane> {
  late final _address = TextEditingController(
    text: widget.store.data.settings.emailAddress,
  );
  final _password = TextEditingController();
  bool _hasPassword = false;
  bool _loading = true;
  bool _busy = false;

  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    NativeCore.readSmtpPassword().then((value) {
      if (!mounted) return;
      setState(() {
        _hasPassword = value != null && value.isNotEmpty;
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _address.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      store.data.settings.emailAddress = _address.text.trim();
      if (_password.text.isNotEmpty) {
        await NativeCore.saveSmtpPassword(_password.text.trim());
        _hasPassword = true;
        _password.clear();
      }
      store.changed();
      await store.saveNow();
      if (mounted) showToast(context, 'Email settings saved');
    } catch (e) {
      if (mounted)
        showToast(context, 'Could not save the password. $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forget() async {
    await NativeCore.forgetSmtpPassword();
    if (!mounted) return;
    setState(() => _hasPassword = false);
    showToast(context, 'The app password was forgotten.');
  }

  Future<void> _pickTime() async {
    final parts = store.data.settings.emailTime.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 17,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 30,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'When should the report go?',
    );
    if (picked == null) return;
    setState(() {
      store.data.settings.emailTime =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      store.changed();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _Pane(
      title: 'Email the day report',
      subtitle: 'Through the shop’s own Gmail account. Nothing else in Sora ever reaches the network.',
      children: [
        SoraField(
          controller: _address,
          label: 'Shop Gmail address',
          hint: 'shop@gmail.com',
          icon: Icons.alternate_email_rounded,
        ),
        const SizedBox(height: 13),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SoraField(
                controller: _password,
                label: 'Google App Password',
                hint: _loading
                    ? 'Checking…'
                    : _hasPassword
                    ? 'Saved — type to replace'
                    : '16 characters',
                icon: Icons.password_rounded,
                obscure: true,
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 23),
              child: StatusPill(
                label: _hasPassword
                    ? 'SAVED IN CREDENTIAL MANAGER'
                    : 'NOT SAVED',
                color: _hasPassword ? p.success : p.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (_hasPassword)
              GlassButton(
                label: 'Forget password',
                icon: Icons.delete_outline_rounded,
                dense: true,
                danger: true,
                onPressed: _forget,
              ),
            const Spacer(),
            GlassButton(
              label: 'Save email settings',
              icon: Icons.check_rounded,
              primary: true,
              loading: _busy,
              onPressed: _save,
            ),
          ],
        ),
        const SizedBox(height: 20),
        SwitchRow(
          title: 'Send the day report on its own',
          subtitle: 'Once a day while the app is open. If there is no connection, the report waits and tries again.',
          value: store.data.settings.autoEmail,
          onChanged: (v) {
            store.data.settings.autoEmail = v;
            store.changed();
            setState(() {});
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            GlassButton(
              label: 'Time  ${store.data.settings.emailTime}',
              icon: Icons.schedule_rounded,
              dense: true,
              onPressed: _pickTime,
            ),
            const SizedBox(width: 10),
            Text(
              'Two PDFs go together: the day report and the sales history.',
              style: TextStyle(fontSize: 10.5, color: p.faint),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _Note(
          icon: Icons.key_rounded,
          text:
              'Gmail will not accept an ordinary account password from another program. Make an App Password in the Google account’s security settings, then paste it here. '
              'It goes into Windows Credential Manager — a backup of the shop’s data file carries no password with it.',
        ),
      ],
    );
  }
}

// --------------------------------------------------------------- danger zone

class _DangerPane extends StatefulWidget {
  final Store store;
  const _DangerPane({super.key, required this.store});
  @override
  State<_DangerPane> createState() => _DangerPaneState();
}

class _DangerPaneState extends State<_DangerPane> {
  Store get store => widget.store;

  Future<void> _reset({required bool everything}) async {
    final p = context.palette;
    final confirmed = await showSoraDialog<bool>(
      context,
      maxWidth: 470,
      builder: (context) => _ResetDialog(everything: everything),
    );
    if (confirmed != true) return;
    try {
      if (everything) {
        await store.resetEverything();
        if (mounted)
          showToast(context, 'Everything is blank. The backup was kept.');
      } else {
        await store.resetSalesAndStock();
        if (mounted) {
          setState(() {});
          showToast(context, 'Sales and stock cleared. The backup was kept.');
        }
      }
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _Pane(
      title: 'Danger zone',
      subtitle: 'Both of these take a backup first, and stop if that backup cannot be written.',
      children: [
        _DangerCard(
          icon: Icons.restart_alt_rounded,
          title: 'Reset sales & stock',
          body:
              'Clears the Ledger, the Overview history and every held sale. Every product stays, with its price, cost and category, but its stock goes to zero. '
              'Meant for a fresh physical stock count, or wiping test data before going live.',
          action: GlassButton(
            label: 'Reset sales & stock',
            danger: true,
            icon: Icons.restart_alt_rounded,
            onPressed: () => _reset(everything: false),
          ),
        ),
        const SizedBox(height: 12),
        _DangerCard(
          icon: Icons.delete_forever_outlined,
          title: 'Reset all data',
          body:
              'Wipes everything back to a blank install: products, sales, categories, settings, the staff list and their passwords. '
              'Sora will ask you to set up the first owner again, just like the first run.',
          action: GlassButton(
            label: 'Reset everything',
            danger: true,
            icon: Icons.delete_forever_outlined,
            onPressed: () => _reset(everything: true),
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.raised,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.hairline),
          ),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, size: 16, color: p.faint),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  store.rootDir.path,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: p.muted,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: store.rootDir.path)),
                child: const Text('Copy path', style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: () => NativeCore.openFile(store.rootDir.path),
                child: const Text(
                  'Open folder',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Sora PoS · v$kAppVersion  ·  Rust + Flutter  ·  Offline and private',
          style: TextStyle(fontSize: 10, color: p.faint),
        ),
      ],
    );
  }
}

class _ResetDialog extends StatefulWidget {
  final bool everything;
  const _ResetDialog({required this.everything});
  @override
  State<_ResetDialog> createState() => _ResetDialogState();
}

class _ResetDialogState extends State<_ResetDialog> {
  final _confirm = TextEditingController();
  bool get _ready => _confirm.text.trim().toUpperCase() == 'RESET';

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SoraDialog(
      title: widget.everything ? 'Reset everything?' : 'Reset sales & stock?',
      subtitle: widget.everything
          ? 'This is the blank install. Products, sales, settings and people all go.'
          : 'Sales, refunds, held sales and stock counts are cleared. Products and prices stay.',
      icon: Icons.warning_amber_rounded,
      accent: p.danger,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: p.danger.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.danger.withValues(alpha: 0.22)),
            ),
            child: Text(
              'A backup is taken into the backups folder first. If it cannot be written, nothing is reset.',
              style: TextStyle(fontSize: 11.5, color: p.muted, height: 1.5),
            ),
          ),
          const SizedBox(height: 14),
          SoraField(
            controller: _confirm,
            autofocus: true,
            label: 'Type RESET to continue',
            hint: 'RESET',
            icon: Icons.keyboard_rounded,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        GlassButton(
          label: 'Keep everything',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        GlassButton(
          label: widget.everything ? 'Reset everything' : 'Reset sales & stock',
          danger: true,
          onPressed: _ready ? () => Navigator.of(context).pop(true) : null,
        ),
      ],
    );
  }
}

class _DangerCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget action;
  const _DangerCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
  });
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      decoration: BoxDecoration(
        color: p.danger.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.danger.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: p.danger.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: p.danger),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: p.muted,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 12),
                action,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ shared

class _Pane extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? trailing;
  const _Pane({
    required this.title,
    required this.subtitle,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: p.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: p.muted,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
        const SizedBox(height: 20),
        ...children,
      ],
    );
  }
}

class _Note extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Note({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: p.raised,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: p.faint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 10.5, color: p.faint, height: 1.55),
            ),
          ),
        ],
      ),
    );
  }
}
