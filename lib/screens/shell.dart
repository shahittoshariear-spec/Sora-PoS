import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analytics.dart';
import '../cart.dart';
import '../format.dart';
import '../models.dart';
import '../store.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import '../widgets/authorize.dart';
import 'ledger.dart';
import 'overview.dart';
import 'reports.dart';
import 'setup.dart';
import 'stock.dart';
import 'till.dart';

class AppShell extends StatefulWidget {
  final Store store;
  final CartController cart;
  const AppShell({super.key, required this.store, required this.cart});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  final _tillKey = GlobalKey<TillScreenState>();
  final _stockKey = GlobalKey<StockScreenState>();
  final _reportsKey = GlobalKey<ReportsScreenState>();
  final Map<String, Widget> _pages = {};
  final Map<String, int> _pageEpochs = {};
  final Set<String> _visited = {};
  int _epoch = 0;
  late final AnimationController _pageFade;

  static const _sectionIds = [
    'till',
    'stock',
    'ledger',
    'overview',
    'reports',
    'setup',
  ];

  String _section =
      _sectionIds.contains(Platform.environment['SORA_START_SECTION'])
      ? Platform.environment['SORA_START_SECTION']!
      : 'till';
  String? _approvedSection;
  DateTime _now = DateTime.now();
  Timer? _clock;
  Timer? _holdTimer;
  String? _holdingAction;

  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    _pageFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 170),
      value: 1,
    );
    store.addListener(_invalidatePages);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  void _invalidatePages() {
    _epoch++;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    store.removeListener(_invalidatePages);
    _pageFade.dispose();
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _clock?.cancel();
    _holdTimer?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------- navigation

  String get _title => switch (_section) {
    'stock' => 'Stock',
    'ledger' => 'Ledger',
    'overview' => 'Overview',
    'reports' => 'Reports',
    'setup' => 'Setup',
    _ => 'Till',
  };

  String get _subtitle => switch (_section) {
    'stock' => 'The shelf, its prices, and everything on it.',
    'ledger' => 'Every sale and return, ready to reprint.',
    'overview' => 'The shop at a glance.',
    'reports' => 'The day’s figures, ready to send.',
    'setup' => 'Shape Sora around your shop.',
    _ => 'Ring up, scan, hold, and take payment.',
  };

  Future<bool> goTo(String section) async {
    if (section == _section) return true;
    if (!store.mayOpen(section)) {
      await ownerOnly(context);
      return false;
    }
    String? approved;
    if (store.needsApproval(section) && _approvedSection != section) {
      final approver = await askApproval(
        context,
        store,
        reason: section == 'stock'
            ? 'Stock sits behind an owner or manager. Type their password to look in.'
            : 'The Ledger sits behind an owner or manager. Type their password to look in.',
      );
      if (approver == null) return false;
      approved = section;
    } else if (store.needsApproval(section)) {
      approved = section;
    }
    if (!mounted) return false;
    setState(() {
      _section = section;
      _approvedSection = approved;
    });
    if (!MediaQuery.disableAnimationsOf(context)) _pageFade.forward(from: 0);
    return true;
  }

  Future<void> _runAfterNavigate(String section, VoidCallback action) async {
    final ok = await goTo(section);
    if (!ok) return;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (mounted) action();
  }

  void _signOut() {
    if (widget.cart.lines.isNotEmpty) {
      store.recordCartCleared(
        widget.cart.lines,
        reason: 'signed out with items on the till',
      );
    }
    widget.cart.clear();
    store.signOut();
  }

  Future<void> _confirmSignOut() async {
    final result = await showSoraDialog<bool>(
      context,
      maxWidth: 410,
      builder: (context) => SoraDialog(
        title: 'Sign out?',
        subtitle:
            'The till closes for ${store.current?.name ?? 'you'}. Nothing in the shop is lost.',
        icon: Icons.logout_rounded,
        child: const SizedBox.shrink(),
        actions: [
          GlassButton(
            label: 'Stay',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          GlassButton(
            label: 'Sign out',
            icon: Icons.logout_rounded,
            danger: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (result == true) _signOut();
  }

  // --------------------------------------------------------------- shortcuts

  String? _comboFor(KeyEvent event) {
    final label = event.logicalKey.keyLabel;
    const modifiers = {'control', 'shift', 'alt', 'meta', 'caps lock', 'fn'};
    if (label.trim().isEmpty || modifiers.contains(label.toLowerCase()))
      return null;
    final parts = <String>[];
    if (HardwareKeyboard.instance.isControlPressed) parts.add('Ctrl');
    if (HardwareKeyboard.instance.isAltPressed) parts.add('Alt');
    if (HardwareKeyboard.instance.isShiftPressed) parts.add('Shift');
    if (HardwareKeyboard.instance.isMetaPressed) parts.add('Meta');
    parts.add(label.toUpperCase());
    return parts.join('+');
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    return _handleShortcut(event)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  bool _onHardwareKey(KeyEvent event) => _handleShortcut(event);

  bool _handleShortcut(KeyEvent event) {
    if (!mounted) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    final combo = _comboFor(event);
    if (combo == null) return false;
    ShortcutBinding? binding;
    for (final b in store.data.shortcuts.values) {
      if (b.keys.isEmpty) continue;
      if (b.keys.toLowerCase() == combo.toLowerCase()) {
        binding = b;
        break;
      }
    }
    if (binding == null) return false;
    final action = binding.action;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event is KeyRepeatEvent) return true;
      if (binding.hold) {
        _holdingAction = action;
        _holdTimer?.cancel();
        _holdTimer = Timer(const Duration(milliseconds: 650), () {
          if (_holdingAction == action) {
            _holdTimer = null;
            _fireShortcut(action);
          }
        });
      } else {
        _fireShortcut(action);
      }
      return true;
    }
    if (event is KeyUpEvent && binding.hold && _holdingAction == action) {
      _holdTimer?.cancel();
      _holdTimer = null;
      _holdingAction = null;
      return true;
    }
    return false;
  }

  void _fireShortcut(String action) {
    switch (action) {
      case 'go.till':
        goTo('till');
      case 'go.stock':
        goTo('stock');
      case 'go.ledger':
        goTo('ledger');
      case 'go.overview':
        goTo('overview');
      case 'go.reports':
        goTo('reports');
      case 'go.setup':
        goTo('setup');
      case 'focus.search':
        _runAfterNavigate('till', () => _tillKey.currentState?.focusSearch());
      case 'pay':
        _runAfterNavigate('till', () => _tillKey.currentState?.openPayment());
      case 'hold':
        _runAfterNavigate('till', () => _tillKey.currentState?.holdSale());
      case 'toggle.products':
        _runAfterNavigate(
          'till',
          () => _tillKey.currentState?.toggleProducts(),
        );
      case 'add.product':
        _runAfterNavigate('stock', () => _stockKey.currentState?.startAdd());
      case 'clear.filter':
        _runAfterNavigate('stock', () => _stockKey.currentState?.clearFilter());
      case 'delete.ticked':
        _runAfterNavigate(
          'stock',
          () => _stockKey.currentState?.deleteTicked(),
        );
      case 'email.report':
        if (!store.isOwner) {
          ownerOnly(context);
        } else {
          _runAfterNavigate(
            'reports',
            () => _reportsKey.currentState?.sendEmail(),
          );
        }
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final appearance = store.data.appearance;
    final topNav = appearance.navPosition == 'top';
    return AuroraBackground(
      palette: p,
      animate: !MediaQuery.disableAnimationsOf(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1180;
              if (appearance.dockNav) {
                return Stack(
                  children: [
                    Positioned.fill(
                      child: _mainContent(topNav: false, dock: true),
                    ),
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 14,
                      child: Center(
                        child: _CommandDock(
                          store: store,
                          section: _section,
                          onGo: goTo,
                          onSignOut: _confirmSignOut,
                        ),
                      ),
                    ),
                  ],
                );
              }
              if (topNav) {
                return Column(
                  children: [
                    _TopNav(
                      store: store,
                      section: _section,
                      rail: !wide,
                      now: _now,
                      onGo: goTo,
                      onSignOut: _confirmSignOut,
                    ),
                    Expanded(child: _mainContent(topNav: true)),
                  ],
                );
              }
              final rail = constraints.maxWidth < 1260;
              return Row(
                children: [
                  _SideNav(
                    store: store,
                    section: _section,
                    rail: rail,
                    now: _now,
                    onGo: goTo,
                    onSignOut: _confirmSignOut,
                  ),
                  Expanded(child: _mainContent(topNav: false)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _mainContent({required bool topNav, bool dock = false}) {
    return Column(
      children: [
        _PageHeader(
          title: _title,
          subtitle: _subtitle,
          now: _now,
          store: store,
          lowStock: lowStockProducts(store.data).length,
          showPulse: store.isOwner && _section != 'till',
          onLowStock: () => goTo(store.isOwner ? 'overview' : 'stock'),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, dock ? 110 : 20),
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _pageFade,
                curve: Curves.easeOutCubic,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  for (final id in _sectionIds)
                    Positioned.fill(
                      child: Offstage(
                        offstage: id != _section,
                        child: TickerMode(
                          enabled: id == _section,
                          child: _visited.contains(id) || id == _section
                              ? _cachedPage(id)
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _cachedPage(String section) {
    _visited.add(section);
    final cached = _pages[section];
    if (cached != null && _pageEpochs[section] == _epoch) return cached;
    final page = _pageFor(section);
    _pages[section] = page;
    _pageEpochs[section] = _epoch;
    return page;
  }

  Widget _pageFor(String section) {
    switch (section) {
      case 'stock':
        return StockScreen(key: _stockKey, store: store);
      case 'ledger':
        return LedgerScreen(store: store);
      case 'overview':
        return OverviewScreen(store: store);
      case 'reports':
        return ReportsScreen(key: _reportsKey, store: store);
      case 'setup':
        return SetupScreen(store: store);
      default:
        return TillScreen(
          key: _tillKey,
          store: store,
          cart: widget.cart,
          onOpenStock: () => goTo('stock'),
          onOpenLedger: () => goTo('ledger'),
        );
    }
  }
}

class _PageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final DateTime now;
  final Store store;
  final int lowStock;
  final bool showPulse;
  final VoidCallback onLowStock;

  const _PageHeader({
    required this.title,
    required this.subtitle,
    required this.now,
    required this.store,
    required this.lowStock,
    required this.showPulse,
    required this.onLowStock,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final withPulse = showPulse && MediaQuery.sizeOf(context).width >= 1180;
    final hourly = List<double>.filled(12, 0);
    var todaySales = 0.0;
    var todayCount = 0;
    if (withPulse) {
      final dayStart = DateTime(now.year, now.month, now.day);
      final dayEnd = dayStart.add(const Duration(days: 1));
      // Sales are appended in order; walk back only through today.
      for (var i = store.data.sales.length - 1; i >= 0; i--) {
        final sale = store.data.sales[i];
        if (sale.at.isBefore(dayStart)) break;
        if (!sale.at.isBefore(dayEnd) || sale.voided) continue;
        todaySales += sale.total;
        todayCount++;
        final bucket = (sale.at.hour ~/ 2).clamp(0, 11).toInt();
        hourly[bucket] += sale.total;
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.7,
                    color: p.text,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12.5, color: p.muted),
                ),
              ],
            ),
          ),
          if (withPulse) ...[
            SoraPulse(
              values: hourly,
              amount: store.fmt(todaySales),
              caption: '$todayCount ${plural(todayCount, 'sale')} today',
            ),
            const SizedBox(width: 8),
          ],
          if (store.data.settings.demo) ...[
            const StatusPill(
              label: 'DEMO DATA',
              icon: Icons.auto_awesome_rounded,
            ),
            const SizedBox(width: 8),
          ],
          if (lowStock > 0) ...[
            GestureDetector(
              onTap: onLowStock,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: StatusPill(
                  label: '$lowStock low',
                  color: p.warning,
                  icon: Icons.warning_amber_rounded,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          GlassPanel(
            blur: 14,
            radius: 12,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 15, color: p.faint),
                const SizedBox(width: 7),
                Text(
                  timeShort(now),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: p.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  dateMedium(now),
                  style: TextStyle(fontSize: 11, color: p.faint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavDef {
  final String id;
  final String label;
  final IconData icon;
  const _NavDef(this.id, this.label, this.icon);
}

const _navItems = <_NavDef>[
  _NavDef('till', 'Till', Icons.shopping_bag_rounded),
  _NavDef('stock', 'Stock', Icons.inventory_2_rounded),
  _NavDef('ledger', 'Ledger', Icons.receipt_long_rounded),
  _NavDef('overview', 'Overview', Icons.insights_rounded),
  _NavDef('reports', 'Reports', Icons.description_rounded),
  _NavDef('setup', 'Setup', Icons.tune_rounded),
];

class _SideNav extends StatelessWidget {
  final Store store;
  final String section;
  final bool rail;
  final DateTime now;
  final Future<bool> Function(String) onGo;
  final VoidCallback onSignOut;

  const _SideNav({
    required this.store,
    required this.section,
    required this.rail,
    required this.now,
    required this.onGo,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final staff = store.current;
    final holds = store.data.holds.length;
    final low = lowStockProducts(store.data).length;
    return SizedBox(
      width: rail ? 82 : 246,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 0, 14),
        child: GlassPanel(
          blur: 28,
          radius: 26,
          height: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (rail)
                Center(child: ThemedMark(palette: p, size: 40))
              else
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(
                    children: [
                      ThemedMark(palette: p, size: 38),
                      const SizedBox(width: 11),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SORA',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 4.5,
                              color: p.text,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'POINT OF SALE',
                            style: overlineStyle(p, color: p.faint),
                          ),
                          const SizedBox(height: 7),
                          SoraSignature(palette: p, height: 15),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              if (!rail)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 8),
                  child: Text('WORKSPACE', style: overlineStyle(p)),
                ),
              for (final item in _navItems.where(
                (item) => store.mayOpen(item.id),
              ))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _NavTile(
                    item: item,
                    selected: section == item.id,
                    rail: rail,
                    locked: false,
                    approval: false,
                    badge: item.id == 'till'
                        ? holds
                        : (item.id == 'stock' && low > 0 ? low : null),
                    badgeColor: item.id == 'stock' ? p.warning : p.accent,
                    onTap: () => onGo(item.id),
                  ),
                ),
              const Spacer(),
              if (!rail)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: p.accent.withValues(alpha: 0.14),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.wifi_off_rounded, size: 15, color: p.accent),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Offline and private',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: p.muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              if (staff != null)
                _UserCard(staff: staff, rail: rail, onSignOut: onSignOut)
              else
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    'Not signed in',
                    style: TextStyle(fontSize: 11, color: p.faint),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandDock extends StatelessWidget {
  final Store store;
  final String section;
  final Future<bool> Function(String) onGo;
  final VoidCallback onSignOut;

  const _CommandDock({
    required this.store,
    required this.section,
    required this.onGo,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final staff = store.current;
    final holds = store.data.holds.length;
    final low = lowStockProducts(store.data).length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = MediaQuery.sizeOf(context).width < 1120;
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: GlassPanel(
            radius: 24,
            padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
            tint: p.isLight ? const Color(0xF6F8F9FC) : const Color(0xF2080D14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: p.isLight ? 0.75 : 0.075),
                Colors.white.withValues(alpha: 0.015),
                p.accent.withValues(alpha: 0.035),
              ],
            ),
            shadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: p.isLight ? 0.16 : 0.42),
                blurRadius: 42,
                offset: const Offset(0, 20),
              ),
              BoxShadow(
                color: p.accent.withValues(alpha: 0.10),
                blurRadius: 32,
                spreadRadius: -12,
              ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 3, right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ThemedMark(palette: p, size: 31),
                      if (!compact) ...[
                        const SizedBox(width: 9),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SORA',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 3.4,
                                color: p.text,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SoraSignature(palette: p, height: 13),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 30,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: p.hairline,
                ),
                for (final item in _navItems.where(
                  (item) => store.mayOpen(item.id),
                ))
                  _DockItem(
                    item: item,
                    selected: section == item.id,
                    compact: compact,
                    badge: item.id == 'till'
                        ? holds
                        : (item.id == 'stock' && low > 0 ? low : null),
                    badgeColor: item.id == 'stock' ? p.warning : p.accent,
                    onTap: () => onGo(item.id),
                  ),
                Container(
                  width: 1,
                  height: 30,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: p.hairline,
                ),
                if (staff != null)
                  Tooltip(
                    message:
                        '${staff.name} · ${staff.role.label} — click to sign out',
                    child: GestureDetector(
                      onTap: onSignOut,
                      child: Container(
                        height: 42,
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 7 : 9,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(13),
                          color: p.raised.withValues(
                            alpha: p.isLight ? 0.5 : 0.35,
                          ),
                          border: Border.all(color: p.hairline),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: p.accentGradient,
                              ),
                              child: Text(
                                staff.initials,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: p.accent.computeLuminance() > 0.47
                                      ? const Color(0xFF08120F)
                                      : Colors.white,
                                ),
                              ),
                            ),
                            if (!compact) ...[
                              const SizedBox(width: 8),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 96,
                                    ),
                                    child: Text(
                                      staff.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: p.text,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    staff.role.label,
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      color: p.faint,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.logout_rounded,
                                size: 13,
                                color: p.faint,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DockItem extends StatefulWidget {
  final _NavDef item;
  final bool selected;
  final bool compact;
  final int? badge;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _DockItem({
    required this.item,
    required this.selected,
    required this.compact,
    required this.onTap,
    this.badge,
    this.badgeColor,
  });

  @override
  State<_DockItem> createState() => _DockItemState();
}

class _DockItemState extends State<_DockItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 42,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 11 : 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            gradient: selected
                ? LinearGradient(
                    colors: [
                      p.accent.withValues(alpha: 0.22),
                      p.accent.withValues(alpha: 0.055),
                    ],
                  )
                : null,
            color: selected
                ? null
                : _hover
                ? Colors.white.withValues(alpha: p.isLight ? 0.35 : 0.04)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? p.accent.withValues(alpha: 0.32)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.item.icon,
                size: 17,
                color: selected ? p.accent : p.muted,
              ),
              if (!widget.compact) ...[
                const SizedBox(width: 7),
                Text(
                  widget.item.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? p.accent : p.muted,
                  ),
                ),
              ],
              if (widget.badge != null && widget.badge! > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: (widget.badgeColor ?? p.accent).withValues(
                      alpha: 0.16,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${widget.badge}',
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      color: widget.badgeColor ?? p.accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatefulWidget {
  final _NavDef item;
  final bool selected;
  final bool rail;
  final bool locked;
  final bool approval;
  final int? badge;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _NavTile({
    required this.item,
    required this.selected,
    required this.rail,
    required this.locked,
    required this.approval,
    required this.onTap,
    this.badge,
    this.badgeColor,
  });

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final selected = widget.selected;
    final onAccent = p.accent.computeLuminance() > 0.47
        ? const Color(0xFF08120F)
        : Colors.white;
    final content = Container(
      height: 44,
      padding: EdgeInsets.symmetric(horizontal: widget.rail ? 0 : 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: selected
            ? LinearGradient(
                colors: [
                  p.accent.withValues(alpha: 0.24),
                  p.accent.withValues(alpha: 0.075),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: selected ? null : (_hover ? p.raised : Colors.transparent),
        border: selected
            ? Border.all(color: p.accent.withValues(alpha: 0.30))
            : null,
        boxShadow: selected
            ? [
                BoxShadow(
                  color: p.accent.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: widget.rail
          ? Center(
              child: Icon(
                widget.item.icon,
                size: 19,
                color: selected ? p.accent : p.muted,
              ),
            )
          : Row(
              children: [
                Icon(
                  widget.item.icon,
                  size: 19,
                  color: selected ? p.accent : (_hover ? p.text : p.muted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.item.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? p.accent : p.muted,
                    ),
                  ),
                ),
                if (widget.badge != null && widget.badge! > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (widget.badgeColor ?? p.accent).withValues(
                        alpha: 0.15,
                      ),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      '${widget.badge}',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: widget.badgeColor ?? p.accent,
                      ),
                    ),
                  )
                else if (widget.locked || widget.approval)
                  Icon(
                    widget.approval
                        ? Icons.key_rounded
                        : Icons.lock_outline_rounded,
                    size: 13,
                    color: selected
                        ? p.accent.withValues(alpha: 0.65)
                        : p.faint,
                  ),
              ],
            ),
    );
    final tappable = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onTap, child: content),
    );
    return widget.rail
        ? Tooltip(message: widget.item.label, child: tappable)
        : tappable;
  }
}

class _UserCard extends StatelessWidget {
  final Staff staff;
  final bool rail;
  final VoidCallback onSignOut;

  const _UserCard({
    required this.staff,
    required this.rail,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final avatar = Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            p.accent.withValues(alpha: 0.32),
            p.accent.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: p.accent.withValues(alpha: 0.22)),
      ),
      child: Text(
        staff.initials,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: p.accent,
        ),
      ),
    );
    if (rail) {
      return Tooltip(
        message: '${staff.name} · ${staff.role.label}',
        child: GestureDetector(
          onTap: onSignOut,
          child: Center(child: avatar),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
      decoration: BoxDecoration(
        color: p.raised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  staff.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  staff.role.label,
                  style: TextStyle(fontSize: 9.5, color: p.muted),
                ),
              ],
            ),
          ),
          Tooltip(
            message: 'Sign out',
            child: IconButton(
              onPressed: onSignOut,
              icon: Icon(Icons.logout_rounded, size: 15, color: p.faint),
              splashRadius: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopNav extends StatelessWidget {
  final Store store;
  final String section;
  final bool rail;
  final DateTime now;
  final Future<bool> Function(String) onGo;
  final VoidCallback onSignOut;

  const _TopNav({
    required this.store,
    required this.section,
    required this.rail,
    required this.now,
    required this.onGo,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final staff = store.current;
    final holds = store.data.holds.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: GlassPanel(
        blur: 28,
        radius: 22,
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            ThemedMark(palette: p, size: 36),
            if (!rail) ...[
              const SizedBox(width: 10),
              Text(
                'SORA',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                  color: p.text,
                ),
              ),
              const SizedBox(width: 8),
              SoraSignature(palette: p, height: 15),
            ],
            const SizedBox(width: 18),
            Expanded(
              child: Row(
                children: _navItems.where((item) => store.mayOpen(item.id)).map(
                  (item) {
                    final selected = section == item.id;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Tooltip(
                          message: item.label,
                          child: GestureDetector(
                            onTap: () => onGo(item.id),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              height: 42,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: selected
                                    ? LinearGradient(
                                        colors: [
                                          p.accent.withValues(alpha: 0.24),
                                          p.accent.withValues(alpha: 0.08),
                                        ],
                                      )
                                    : null,
                                color: selected
                                    ? null
                                    : p.raised.withValues(alpha: 0.35),
                                border: Border.all(
                                  color: selected
                                      ? p.accent.withValues(alpha: 0.30)
                                      : p.hairline,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    item.icon,
                                    size: 16,
                                    color: selected ? p.accent : p.muted,
                                  ),
                                  if (!rail) ...[
                                    const SizedBox(width: 7),
                                    Text(
                                      item.label,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        color: selected ? p.accent : p.muted,
                                      ),
                                    ),
                                  ],
                                  if (item.id == 'till' &&
                                      holds > 0 &&
                                      !rail) ...[
                                    const SizedBox(width: 5),
                                    Text(
                                      '$holds',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: selected ? p.accent : p.accent,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ).toList(),
              ),
            ),
            const SizedBox(width: 12),
            if (staff != null)
              Tooltip(
                message:
                    '${staff.name} · ${staff.role.label} — click to sign out',
                child: GestureDetector(
                  onTap: onSignOut,
                  child: Container(
                    height: 38,
                    padding: EdgeInsets.symmetric(horizontal: rail ? 8 : 12),
                    decoration: BoxDecoration(
                      color: p.raised,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: p.hairline),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 15,
                          color: p.accent,
                        ),
                        if (!rail) ...[
                          const SizedBox(width: 7),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 110),
                            child: Text(
                              staff.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: p.text,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
