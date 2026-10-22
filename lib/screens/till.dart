import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analytics.dart';
import '../cart.dart';
import '../format.dart';
import '../models.dart';
import '../services/audio.dart';
import '../services/native.dart';
import '../services/receipts.dart';
import '../store.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import '../widgets/authorize.dart';
import '../widgets/sale_view.dart';

class TillScreen extends StatefulWidget {
  final Store store;
  final CartController cart;
  final VoidCallback? onOpenStock;
  final VoidCallback? onOpenLedger;

  const TillScreen({
    super.key,
    required this.store,
    required this.cart,
    this.onOpenStock,
    this.onOpenLedger,
  });

  @override
  State<TillScreen> createState() => TillScreenState();
}

class TillScreenState extends State<TillScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Till search');
  Timer? _debounce;
  Timer? _scanReset;
  final StringBuffer _scanBuffer = StringBuffer();
  DateTime _lastScanKey = DateTime.fromMillisecondsSinceEpoch(0);
  String _query = '';
  String _categoryId = '';
  int _searchVersion = 0;
  bool _productsVisible = true;
  double _panelFraction = 0.34;
  String _rightView = 'cart';
  final GlobalKey<_TillSplitState> _splitKey = GlobalKey<_TillSplitState>();

  Store get store => widget.store;
  CartController get cart => widget.cart;

  @override
  void initState() {
    super.initState();
    _panelFraction = store.data.settings.tillPanelFraction
        .clamp(0.28, 1.0)
        .toDouble();
    _rightView = store.data.settings.tillRightView == 'receipt'
        ? 'receipt'
        : 'cart';
    cart.addListener(_onCart);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    cart.removeListener(_onCart);
    _debounce?.cancel();
    _scanReset?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onCart() {
    if (mounted) setState(() {});
  }

  void _removeLine(SaleLine line) {
    final before = List<SaleLine>.of(cart.lines);
    store.recordCartLinesRemoved([line], saleBefore: before);
    cart.remove(line.productId);
    focusSearch();
  }

  void _decrementLine(SaleLine line) {
    if (line.qty <= 1) {
      _removeLine(line);
    } else {
      cart.bump(line.productId, -1);
    }
  }

  void _setRightView(String view) {
    if (_rightView == view) return;
    setState(() => _rightView = view);
    store.data.settings.tillRightView = view;
    store.changed();
  }

  void _setPanelFraction(double fraction) {
    final next = fraction.clamp(0.28, 1.0).toDouble();
    _splitKey.currentState?.setFraction(next);
    _panelFraction = next;
    store.data.settings.tillPanelFraction = next;
    store.changed();
  }

  void toggleProducts() {
    setState(() => _productsVisible = !_productsVisible);
    if (!_productsVisible) {
      Future<void>.delayed(const Duration(milliseconds: 120), focusSearch);
    }
  }

  // ---------------------------------------------------------- scan handling

  bool _onHardwareKey(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    if (_searchFocus.hasFocus) return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed)
      return false;
    final now = DateTime.now();
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_scanBuffer.isNotEmpty &&
          now.difference(_lastScanKey) < const Duration(milliseconds: 280)) {
        final code = _scanBuffer.toString();
        _scanBuffer.clear();
        _handleScan(code);
        return true;
      }
      _scanBuffer.clear();
      return false;
    }
    final char = event.character;
    if (char != null &&
        char.isNotEmpty &&
        char.codeUnitAt(0) >= 32 &&
        char != '\n' &&
        char != '\r') {
      if (now.difference(_lastScanKey) > const Duration(milliseconds: 170))
        _scanBuffer.clear();
      _scanBuffer.write(char);
      if (_scanBuffer.length > 64) _scanBuffer.clear();
      _lastScanKey = now;
      _scanReset?.cancel();
      _scanReset = Timer(const Duration(seconds: 2), _scanBuffer.clear);
    }
    return false;
  }

  void _handleScan(String code) {
    final match = store.exactMatch(code);
    if (match == null) {
      showToast(context, 'No single product for “${code.trim()}”', error: true);
      focusSearch();
      return;
    }
    _add(match);
    focusSearch();
  }

  // ---------------------------------------------------------------- search

  void focusSearch() {
    if (!mounted) return;
    _searchFocus.requestFocus();
    _search.selection = TextSelection.collapsed(offset: _search.text.length);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 65), () {
      if (!mounted) return;
      setState(() {
        _query = value;
        _searchVersion++;
      });
    });
  }

  void _submitSearch(String text) {
    final value = text.trim();
    if (value.isEmpty) {
      focusSearch();
      return;
    }
    final match = store.exactMatch(value);
    if (match != null) {
      _add(match);
      _search.clear();
      setState(() {
        _query = '';
        _searchVersion++;
      });
      focusSearch();
      return;
    }
    final results = store.searchProducts(value, categoryId: _categoryId);
    if (results.length == 1) {
      _add(results.first);
      _search.clear();
      setState(() {
        _query = '';
        _searchVersion++;
      });
      focusSearch();
      return;
    }
    showToast(
      context,
      results.isEmpty
          ? 'Nothing matches “$value”.'
          : '${results.length} products match — keep typing, or tap one.',
      error: results.isEmpty,
    );
    focusSearch();
  }

  void _add(Product product) {
    cart.add(product);
    if (product.stock <= 0) {
      showToast(
        context,
        '${product.name} is out of stock — still added to the sale.',
      );
    }
    focusSearch();
  }

  // --------------------------------------------------------------- payments

  Future<void> openPayment() async {
    if (cart.isEmpty) {
      showToast(context, 'Add something to the sale first.');
      return;
    }
    final sale = await showSoraDialog<Sale>(
      context,
      maxWidth: 690,
      dismissible: true,
      builder: (context) =>
          _PaymentDialog(store: store, lines: cart.lines.toList()),
    );
    if (sale == null || !mounted) return;
    await _afterSale(sale);
  }

  Future<void> _afterSale(Sale sale) async {
    cart.clear();
    _search.clear();
    if (mounted) {
      setState(() {
        _query = '';
        _searchVersion++;
      });
    }
    if (store.data.settings.chime) Chime.play();
    final printer = store.data.settings.receiptPrinter;
    if (printer.isNotEmpty) {
      try {
        await NativeCore.printRaw(
          printer,
          escPosBytes(
            saleReceiptText(store, sale),
            cut: store.data.settings.cutPaper,
          ),
        );
      } catch (e) {
        if (mounted)
          showToast(
            context,
            'The sale is saved, but the printer did not take it. $e',
            error: true,
          );
      }
    }
    if (!mounted) return;
    await showReceiptAfterSale(context, store, sale);
    if (mounted) focusSearch();
  }

  // ------------------------------------------------------------------ holds

  Future<void> holdSale() async {
    if (cart.isEmpty) {
      showToast(context, 'There is nothing to hold.');
      return;
    }
    final label = TextEditingController();
    final result = await showSoraDialog<bool>(
      context,
      maxWidth: 440,
      builder: (context) => SoraDialog(
        title: 'Hold this sale',
        subtitle: 'Serve someone else and come back to it whenever you like.',
        icon: Icons.pause_circle_outline_rounded,
        child: SoraField(
          controller: label,
          autofocus: true,
          label: 'A note (optional)',
          hint: 'Table by the window, paying by card…',
          icon: Icons.sticky_note_2_outlined,
          onSubmitted: (_) => Navigator.of(context).pop(true),
        ),
        actions: [
          GlassButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          GlassButton(
            label: 'Hold sale',
            icon: Icons.pause_rounded,
            primary: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (result != true) return;
    await store.holdSale(cart.lines, label: label.text);
    cart.clear();
    label.dispose();
    if (mounted) {
      showToast(context, 'Sale held — find it in the held list.');
      focusSearch();
    }
  }

  Future<void> _showHeld() async {
    await showSoraDialog<void>(
      context,
      maxWidth: 660,
      builder: (context) =>
          _HeldSalesDialog(store: store, cart: cart, onResumed: focusSearch),
    );
  }

  Future<void> _clearCart() async {
    if (cart.isEmpty) return;
    final p = context.palette;
    final confirmed = await showSoraDialog<bool>(
      context,
      maxWidth: 420,
      builder: (context) => SoraDialog(
        title: 'Empty the sale?',
        subtitle: 'The items will leave the till. Held sales are not touched.',
        icon: Icons.delete_sweep_rounded,
        accent: p.danger,
        child: const SizedBox.shrink(),
        actions: [
          GlassButton(
            label: 'Keep it',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          GlassButton(
            label: 'Empty',
            icon: Icons.close_rounded,
            danger: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      store.recordCartCleared(cart.lines);
      cart.clear();
      focusSearch();
    }
  }

  Future<void> _editPrice(SaleLine line) async {
    final p = context.palette;
    final product = store.productById(line.productId);
    final shelfPrice = product?.price ?? line.unitPrice;
    final controller = TextEditingController(
      text: line.unitPrice.toStringAsFixed(2),
    );
    final approved = store.isManagerOrOwner
        ? store.current
        : await askApproval(
            context,
            store,
            reason:
                'A price for one sale needs an owner or manager to allow it.',
          );
    if (approved == null || !mounted) {
      controller.dispose();
      return;
    }
    final result = await showSoraDialog<String>(
      context,
      maxWidth: 460,
      builder: (context) => SoraDialog(
        title: 'A price for this sale',
        subtitle:
            'This changes this sale only. The product keeps its own price.',
        icon: Icons.edit_note_rounded,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: p.raised,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: p.hairline),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      line.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: p.text,
                      ),
                    ),
                  ),
                  Text(
                    'Shelf ${store.fmt(shelfPrice)}',
                    style: TextStyle(fontSize: 11.5, color: p.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SoraField(
              controller: controller,
              autofocus: true,
              label: 'Price charged for this sale',
              icon: Icons.payments_outlined,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onSubmitted: (_) => Navigator.of(context).pop(controller.text),
            ),
            if (approved != store.current) ...[
              const SizedBox(height: 10),
              Text(
                'Allowed by ${approved.name}.',
                style: TextStyle(fontSize: 10.5, color: p.faint),
              ),
            ],
          ],
        ),
        actions: [
          GlassButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
          GlassButton(
            label: 'Set the price',
            icon: Icons.check_rounded,
            primary: true,
            onPressed: () => Navigator.of(context).pop(controller.text),
          ),
        ],
      ),
    );
    if (result == null) {
      controller.dispose();
      return;
    }
    final price = double.tryParse(result.replaceAll(',', '.'));
    if (price == null || price < 0) {
      controller.dispose();
      if (mounted) showToast(context, 'That is not a price.', error: true);
      return;
    }
    cart.setUnitPrice(line.productId, round2(price));
    store.recordAudit(
      kind: 'price_override',
      title: 'A price set for one sale',
      detail:
          '${line.name}: shelf ${store.fmt(shelfPrice)}, charged ${store.fmt(price)}${approved != store.current ? ' · allowed by ${approved.name}' : ''}',
      productId: line.productId,
      before: shelfPrice,
      after: price,
    );
    controller.dispose();
    if (mounted) showToast(context, 'Price set for this sale only.');
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final totals = store.cartTotals(cart.lines);
    final liveText = liveReceiptText(
      store,
      cart.lines,
      totals,
      number: store.data.nextNumber,
      cashier: store.current?.name ?? '',
    );
    return _TillSplit(
      key: _splitKey,
      initialFraction: _panelFraction,
      left: _productsVisible ? _catalog() : _focusModeHint(),
      right: (context, panelWidth, full, dragging) =>
          _salePanel(totals, liveText, panelWidth, full, dragging: dragging),
      onSettled: (fraction) {
        _panelFraction = fraction;
        store.data.settings.tillPanelFraction = fraction;
        store.changed();
      },
    );
  }

  Widget _catalog() {
    final p = context.palette;
    final products = store.searchProducts(_query, categoryId: _categoryId);
    final totalMatches = store.matchCount(_query, categoryId: _categoryId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SoraField(
                controller: _search,
                focusNode: _searchFocus,
                hint: 'Search, scan a barcode, or type a name…',
                icon: Icons.qr_code_scanner_rounded,
                onChanged: _onSearchChanged,
                onSubmitted: _submitSearch,
                suffix: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_search.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _search.clear();
                            _onSearchChanged('');
                            focusSearch();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              size: 15,
                              color: p.faint,
                            ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: p.raised,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: p.hairline),
                        ),
                        child: Text(
                          'ENTER',
                          style: TextStyle(
                            fontSize: 8,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w600,
                            color: p.faint,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            _HeldButton(count: store.data.holds.length, onTap: _showHeld),
            const SizedBox(width: 7),
            GlassIconButton(
              icon: Icons.vertical_split_rounded,
              tooltip: 'Hide the product list  (F11)',
              onPressed: toggleProducts,
              size: 46,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterPill(
                      label: 'All',
                      selected: _categoryId.isEmpty,
                      onTap: () {
                        setState(() {
                          _categoryId = '';
                          _searchVersion++;
                        });
                      },
                    ),
                    const SizedBox(width: 7),
                    for (final c in store.data.categories) ...[
                      FilterPill(
                        label: c.name,
                        selected: _categoryId == c.id,
                        onTap: () {
                          setState(() {
                            _categoryId = c.id;
                            _searchVersion++;
                          });
                        },
                      ),
                      const SizedBox(width: 7),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (totalMatches > products.length)
              Text(
                'Showing ${products.length} of $totalMatches · keep typing',
                style: TextStyle(fontSize: 10.5, color: p.faint),
              )
            else
              Text(
                '$totalMatches ${plural(totalMatches, 'product')}',
                style: TextStyle(fontSize: 10.5, color: p.faint),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: products.isEmpty
              ? EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'Nothing on the shelf matches',
                  message: _query.isEmpty
                      ? 'Add products in Stock, or clear the category filter.'
                      : 'Try a shorter search, or check the barcode.',
                  action: _query.isNotEmpty
                      ? GlassButton(
                          label: 'Clear search',
                          icon: Icons.close_rounded,
                          onPressed: () {
                            _search.clear();
                            _onSearchChanged('');
                            focusSearch();
                          },
                        )
                      : null,
                )
              : Scrollbar(
                  child: GridView.builder(
                    padding: const EdgeInsets.only(right: 4, bottom: 8),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 212,
                          mainAxisExtent: 128,
                          crossAxisSpacing: 11,
                          mainAxisSpacing: 11,
                        ),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return TweenAnimationBuilder<double>(
                        key: ValueKey('${product.id}-$_searchVersion'),
                        tween: Tween(begin: 0, end: 1),
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : Duration(milliseconds: 240 + (index % 10) * 24),
                        curve: Curves.easeOutCubic,
                        builder: (context, t, child) => Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(0, 10 * (1 - t)),
                            child: child,
                          ),
                        ),
                        child: _ProductCard(
                          product: product,
                          category: store.categoryName(product.categoryId),
                          currency: store.currency,
                          lowStock: product.stock <= store.data.shop.lowStock,
                          onTap: () => _add(product),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _focusModeHint() {
    final p = context.palette;
    return Center(
      child: GlassPanel(
        blur: 20,
        radius: 24,
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_off_outlined, size: 34, color: p.faint),
            const SizedBox(height: 14),
            Text(
              'The product list is hidden',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: p.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Keep your eye on the sale. The search still works with F7.',
              style: TextStyle(fontSize: 12, color: p.muted, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            GlassButton(
              label: 'Show products',
              icon: Icons.grid_view_rounded,
              onPressed: toggleProducts,
            ),
          ],
        ),
      ),
    );
  }

  Widget _salePanel(
    CartTotals totals,
    String liveText,
    double panelWidth,
    bool full, {
    bool dragging = false,
  }) {
    final p = context.palette;
    return GlassPanel(
      blur: 30,
      radius: 24,
      shadow: dragging ? const [] : null,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      height: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SALE #${store.data.nextNumber}',
                      style: overlineStyle(p, color: p.accent),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _rightView == 'receipt' ? 'Live receipt' : 'Current sale',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: p.text,
                      ),
                    ),
                  ],
                ),
              ),
              GlassIconButton(
                icon: Icons.shopping_bag_outlined,
                selected: _rightView == 'cart',
                tooltip: 'Cart',
                size: 32,
                onPressed: () => _setRightView('cart'),
              ),
              const SizedBox(width: 4),
              GlassIconButton(
                icon: Icons.receipt_long_outlined,
                selected: _rightView == 'receipt',
                tooltip: 'Live receipt',
                size: 32,
                onPressed: () => _setRightView('receipt'),
              ),
              if (full) ...[
                const SizedBox(width: 4),
                GlassIconButton(
                  icon: Icons.grid_view_rounded,
                  tooltip: 'Show products',
                  size: 32,
                  onPressed: () => _setPanelFraction(0.34),
                ),
              ],
              const SizedBox(width: 4),
              _HeldButton(
                count: store.data.holds.length,
                onTap: _showHeld,
                compact: true,
              ),
              const SizedBox(width: 4),
              GlassIconButton(
                icon: Icons.pause_circle_outline_rounded,
                tooltip: 'Hold this sale  (F9)',
                onPressed: cart.isEmpty ? null : holdSale,
                size: 32,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _rightView == 'receipt'
                ? _liveReceiptBody(panelWidth, liveText)
                : (cart.isEmpty
                      ? EmptyState(
                          icon: Icons.shopping_bag_outlined,
                          art: SoraOrb(palette: p, size: 104),
                          title: 'Ready when you are',
                          message: 'Scan a barcode, search by name, or tap a product.\nThe sale stays here while you look around.',
                          iconSize: 38,
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 8),
                          itemCount: cart.lines.length,
                          separatorBuilder: (_, __) =>
                              Divider(color: p.hairline, height: 15),
                          itemBuilder: (context, index) {
                            final line = cart.lines[index];
                            final product = store.productById(line.productId);
                            final shelf = product?.price;
                            return _CartLine(
                              line: line,
                              currency: store.currency,
                              shelfPrice: shelf,
                              onMinus: () => _decrementLine(line),
                              onPlus: () => cart.bump(line.productId, 1),
                              onRemove: () => _removeLine(line),
                              onEdit: () => _editPrice(line),
                            );
                          },
                        )),
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: p.hairline),
          const SizedBox(height: 12),
          _TotalRow(label: 'Subtotal', value: store.fmt(totals.subtotal)),
          const SizedBox(height: 6),
          _TotalRow(
            label: 'Tax (${numText(store.data.shop.taxRate)}%)',
            value: store.fmt(totals.tax),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Total',
                style: TextStyle(
                  fontSize: 13,
                  color: p.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                store.fmt(totals.total),
                style: TextStyle(
                  fontSize: 29,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                  color: p.text,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GlassButton(
            label: cart.isEmpty
                ? 'Charge'
                : 'Charge ${store.fmt(totals.total)}',
            icon: Icons.arrow_forward_rounded,
            primary: true,
            expand: true,
            onPressed: cart.isEmpty ? null : openPayment,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                'F8',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  color: p.accent.computeLuminance() > 0.47
                      ? const Color(0xFF08120F)
                      : Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: cart.isEmpty ? null : holdSale,
                  child: const Text('Hold'),
                ),
              ),
              Container(width: 1, height: 16, color: p.hairline),
              Expanded(
                child: TextButton(
                  onPressed: cart.isEmpty ? null : _clearCart,
                  child: Text('Clear', style: TextStyle(color: p.danger)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _liveReceiptBody(double panelWidth, String liveText) {
    if (cart.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'The receipt is empty',
        message: 'Add an item and the live receipt writes itself here.',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final paperWidth = math
            .min(panelWidth - 44, 640.0)
            .clamp(280.0, 640.0)
            .toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                StatusPill(
                  label: 'LIVE · NOT PAID',
                  color: context.palette.warning,
                  dot: true,
                ),
                const Spacer(),
                Text(
                  'Updates as the sale is built',
                  style: TextStyle(fontSize: 9.5, color: context.palette.faint),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: ReceiptPaper(
                  text: liveText,
                  width: paperWidth,
                  maxHeight: math.max(240, constraints.maxHeight - 46),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TillSplit extends StatefulWidget {
  final double initialFraction;
  final Widget left;
  final Widget Function(
    BuildContext context,
    double panelWidth,
    bool full,
    bool dragging,
  )
  right;
  final ValueChanged<double> onSettled;

  const _TillSplit({
    super.key,
    required this.initialFraction,
    required this.left,
    required this.right,
    required this.onSettled,
  });

  @override
  State<_TillSplit> createState() => _TillSplitState();
}

class _TillSplitState extends State<_TillSplit>
    with SingleTickerProviderStateMixin {
  late final ValueNotifier<double> _fraction;
  late final ValueNotifier<double> _dragFraction;
  late final AnimationController _snap;
  Animation<double>? _snapAnimation;
  late double _target;
  bool _dragging = false;
  bool _framePending = false;
  bool _motionHeld = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialFraction.clamp(0.28, 1.0).toDouble();
    _fraction = ValueNotifier<double>(initial);
    _dragFraction = ValueNotifier<double>(initial);
    _target = initial;
    _snap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
  }

  @override
  void dispose() {
    if (_motionHeld) SoraMotion.release();
    _snapAnimation?.removeListener(_onSnap);
    _snap.dispose();
    _fraction.dispose();
    _dragFraction.dispose();
    super.dispose();
  }

  static double _snapped(double fraction) {
    const snaps = [0.34, 0.5, 0.75, 1.0];
    var best = snaps.first;
    for (final snap in snaps) {
      if ((fraction - snap).abs() < (fraction - best).abs()) best = snap;
    }
    return best;
  }

  void _onSnap() {
    final animation = _snapAnimation;
    if (animation != null) _fraction.value = animation.value;
  }

  void setFraction(double fraction) {
    final next = fraction.clamp(0.28, 1.0).toDouble();
    _target = next;
    _animateTo(next);
  }

  void _animateTo(double target, {bool releaseMotion = false}) {
    _snapAnimation?.removeListener(_onSnap);
    _snapAnimation = Tween<double>(begin: _fraction.value, end: target).animate(
      CurvedAnimation(parent: _snap, curve: Curves.easeOutCubic),
    )..addListener(_onSnap);
    _snap.forward(from: 0).whenComplete(() {
      if (releaseMotion && mounted && _motionHeld) {
        _motionHeld = false;
        SoraMotion.release();
      }
    });
  }

  /// Pointer events can arrive far faster than frames on a high-poll-rate
  /// mouse. Coalesce them: one guide repaint per frame, never one per event.
  /// The layout is deliberately **not** changed during the gesture — resizing
  /// the whole pane frame by frame is what caused gigabyte raster-cache spikes.
  void _dragDelta(double dx, double available) {
    _target = (_target - dx / available).clamp(0.28, 1.0).toDouble();
    if (_framePending) return;
    _framePending = true;
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      _framePending = false;
      if (!mounted || !_dragging) return;
      _dragFraction.value = _target;
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _dragStart() {
    _snap.stop();
    _snapAnimation?.removeListener(_onSnap);
    _snapAnimation = null;
    _target = _fraction.value;
    _dragFraction.value = _fraction.value;
    SoraMotion.hold();
    _motionHeld = true;
    setState(() => _dragging = true);
  }

  void _dragEnd() {
    final settled = _snapped(_target);
    setState(() => _dragging = false);
    _animateTo(settled, releaseMotion: true);
    widget.onSettled(settled);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        if (available <= 0) return const SizedBox.shrink();
        return ValueListenableBuilder<double>(
          valueListenable: _fraction,
          builder: (context, fraction, _) {
            final full = fraction >= 0.999;
            final panelWidth = full
                ? available
                : math.max(300.0, (available * fraction / 2).round() * 2.0);
            return Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // `widget.left` is an already-built subtree owned by the
                      // till. Repeated drags reuse the same widget instance.
                      if (!full) Expanded(child: widget.left),
                      if (!full)
                        Opacity(
                          opacity: _dragging ? 0 : 1,
                          child: _PanelGrip(
                            onDragStart: _dragStart,
                            onDragUpdate: (dx) => _dragDelta(dx, available),
                            onDragEnd: _dragEnd,
                            onReset: () {
                              setFraction(0.34);
                              widget.onSettled(0.34);
                            },
                          ),
                        ),
                      SizedBox(
                        width: panelWidth,
                        child: widget.right(
                          context,
                          panelWidth,
                          full,
                          _dragging,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_dragging)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ValueListenableBuilder<double>(
                        valueListenable: _dragFraction,
                        builder: (context, guide, _) => RepaintBoundary(
                          key: const ValueKey('till-split-guide'),
                          child: _DragGuide(
                            fraction: guide,
                            available: available,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _DragGuide extends StatelessWidget {
  final double fraction;
  final double available;

  const _DragGuide({required this.fraction, required this.available});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final x = (available * (1 - fraction)).clamp(0.0, available).toDouble();
    final percent = (fraction * 100).round();
    return LayoutBuilder(
      builder: (context, constraints) {
        final top = (constraints.maxHeight * 0.32)
            .clamp(12.0, math.max(12.0, constraints.maxHeight - 52.0))
            .toDouble();
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _GuidePainter(x: x, palette: p),
              ),
            ),
            Positioned(
              left: (x - 42)
                  .clamp(8.0, math.max(8.0, available - 96.0))
                  .toDouble(),
              top: top,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: p.raised.withValues(alpha: 0.94),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      p.accent.withValues(alpha: 0.20),
                      Colors.white.withValues(alpha: 0.03),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: p.accent.withValues(alpha: 0.55)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.30),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.drag_indicator_rounded,
                      size: 14,
                      color: p.accent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$percent%',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: p.text,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GuidePainter extends CustomPainter {
  final double x;
  final SoraPalette palette;
  _GuidePainter({required this.x, required this.palette});

  @override
  void paint(Canvas canvas, Size size) {
    final lineX = x.clamp(0.5, math.max(0.5, size.width - 0.5)).toDouble();
    canvas.drawLine(
      Offset(lineX, 0),
      Offset(lineX, size.height),
      Paint()
        ..color = palette.accent.withValues(alpha: 0.42)
        ..strokeWidth = 7
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8),
    );
    canvas.drawLine(
      Offset(lineX, 0),
      Offset(lineX, size.height),
      Paint()
        ..color = palette.accent.withValues(alpha: 0.9)
        ..strokeWidth = 2,
    );
    canvas.drawLine(
      Offset(lineX, 0),
      Offset(lineX, size.height),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.34)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _GuidePainter old) =>
      old.x != x || old.palette.id != palette.id;
}

class _PanelGrip extends StatefulWidget {
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onReset;

  const _PanelGrip({
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onReset,
  });

  @override
  State<_PanelGrip> createState() => _PanelGripState();
}

class _PanelGripState extends State<_PanelGrip> {
  bool _hover = false;
  bool _active = false;
  bool _started = false;
  double _downX = 0;
  double _lastX = 0;
  DateTime? _lastTapAt;

  void _pointerDown(PointerDownEvent event) {
    _active = true;
    _started = false;
    _downX = event.position.dx;
    _lastX = event.position.dx;
  }

  void _pointerMove(PointerMoveEvent event) {
    if (!_active) return;
    if (!_started) {
      final dx = event.position.dx - _downX;
      if (dx.abs() < 3) return;
      _started = true;
      _lastTapAt = null;
      _lastX = event.position.dx;
      widget.onDragStart();
      widget.onDragUpdate(dx);
      return;
    }
    final dx = event.position.dx - _lastX;
    _lastX = event.position.dx;
    if (dx.abs() >= 0.01) widget.onDragUpdate(dx);
  }

  void _pointerUp(PointerEvent event) {
    if (!_active) return;
    _active = false;
    if (_started) {
      _started = false;
      widget.onDragEnd();
      return;
    }
    final now = DateTime.now();
    final last = _lastTapAt;
    if (last != null && now.difference(last).inMilliseconds < 320) {
      _lastTapAt = null;
      widget.onReset();
    } else {
      _lastTapAt = now;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        key: const ValueKey('till-split-grip'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: _pointerDown,
        onPointerMove: _pointerMove,
        onPointerUp: _pointerUp,
        onPointerCancel: _pointerUp,
        child: Container(
          width: 18,
          alignment: Alignment.center,
          color: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: _hover ? 4 : 2,
            height: 44,
            decoration: BoxDecoration(
              color: _hover ? p.accent : p.hairline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  const _TotalRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: p.muted)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            color: p.text,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _CartLine extends StatefulWidget {
  final SaleLine line;
  final String currency;
  final double? shelfPrice;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onRemove;
  final VoidCallback onEdit;

  const _CartLine({
    required this.line,
    required this.currency,
    this.shelfPrice,
    required this.onMinus,
    required this.onPlus,
    required this.onRemove,
    required this.onEdit,
  });

  @override
  State<_CartLine> createState() => _CartLineState();
}

class _CartLineState extends State<_CartLine> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final overridden =
        widget.shelfPrice != null &&
        (widget.shelfPrice! - widget.line.unitPrice).abs() > 0.001;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.line.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: p.text,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '${widget.currency}${moneyPlain(widget.line.unitPrice)}',
                      style: TextStyle(fontSize: 10.5, color: p.faint),
                    ),
                    if (overridden) ...[
                      const SizedBox(width: 5),
                      Text(
                        'was ${widget.currency}${moneyPlain(widget.shelfPrice!)}',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: p.danger,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            height: 27,
            decoration: BoxDecoration(
              color: p.raised,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MiniStep(icon: Icons.remove_rounded, onTap: widget.onMinus),
                SizedBox(
                  width: 20,
                  child: Text(
                    numText(widget.line.qty),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: p.text,
                    ),
                  ),
                ),
                _MiniStep(icon: Icons.add_rounded, onTap: widget.onPlus),
              ],
            ),
          ),
          SizedBox(
            width: 65,
            child: Text(
              '${widget.currency}${moneyPlain(widget.line.total)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: p.text,
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: _hover ? 1 : 0.35,
            duration: const Duration(milliseconds: 150),
            child: Column(
              children: [
                _MiniAction(
                  icon: Icons.edit_outlined,
                  onTap: widget.onEdit,
                  tooltip: 'A price for this sale',
                ),
                _MiniAction(
                  icon: Icons.close_rounded,
                  onTap: widget.onRemove,
                  tooltip: 'Remove',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStep extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MiniStep({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 23,
        height: 25,
        child: Icon(icon, size: 12, color: p.muted),
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  const _MiniAction({required this.icon, required this.onTap, this.tooltip});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final child = GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 25,
        height: 24,
        child: Icon(icon, size: 12, color: p.faint),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

class _HeldButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  final bool compact;
  const _HeldButton({
    required this.count,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: 'Held sales',
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: compact ? 36 : 46,
            height: compact ? 36 : 46,
            decoration: BoxDecoration(
              color: p.raised,
              borderRadius: BorderRadius.circular(compact ? 12 : 14),
              border: Border.all(color: p.hairline),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.pause_circle_outline_rounded,
                  size: compact ? 16 : 19,
                  color: p.muted,
                ),
                if (count > 0)
                  Positioned(
                    top: compact ? 4 : 7,
                    right: compact ? 4 : 7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: p.accent,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 7.5,
                          fontWeight: FontWeight.w700,
                          color: p.accent.computeLuminance() > 0.47
                              ? const Color(0xFF08120F)
                              : Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatefulWidget {
  final Product product;
  final String category;
  final String currency;
  final bool lowStock;
  final VoidCallback onTap;

  const _ProductCard({
    required this.product,
    required this.category,
    required this.currency,
    required this.lowStock,
    required this.onTap,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final out = widget.product.stock <= 0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            color: _hover ? p.accent.withValues(alpha: 0.10) : p.glassTint,
            gradient: p.matte
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _hover
                        ? [
                            p.accent.withValues(alpha: 0.15),
                            p.accent.withValues(alpha: 0.045),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.055),
                            Colors.white.withValues(alpha: 0.014),
                          ],
                  ),
            border: Border.all(
              color: _hover ? p.accent.withValues(alpha: 0.45) : p.hairline,
              width: _hover ? 1.2 : 1,
            ),
            boxShadow: _hover && !p.matte
                ? [
                    BoxShadow(
                      color: p.accent.withValues(alpha: 0.16),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.category.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: overlineStyle(
                        p,
                        color: _hover ? p.accent : p.faint,
                      ),
                    ),
                  ),
                  if (out)
                    StatusPill(label: 'OUT', color: p.danger)
                  else if (widget.lowStock)
                    StatusPill(
                      label: '${numText(widget.product.stock)} left',
                      color: p.warning,
                    ),
                  if (_hover && !out)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.only(left: 6),
                      decoration: BoxDecoration(
                        color: p.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.add_rounded,
                        size: 14,
                        color: p.accent.computeLuminance() > 0.47
                            ? const Color(0xFF08120F)
                            : Colors.white,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  widget.product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    letterSpacing: -0.15,
                    color: p.text,
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${widget.currency}${moneyPlain(widget.product.price)}',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: p.text,
                    ),
                  ),
                  const Spacer(),
                  if (!out && !widget.lowStock)
                    Text(
                      '${numText(widget.product.stock)} on shelf',
                      style: TextStyle(fontSize: 9.5, color: p.faint),
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

class _PaymentLegend extends StatelessWidget {
  final Color color;
  final String label;
  const _PaymentLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: p.faint,
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ payment

class _PaymentDialog extends StatefulWidget {
  final Store store;
  final List<SaleLine> lines;
  const _PaymentDialog({required this.store, required this.lines});

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _cash = TextEditingController();
  final _card = TextEditingController();
  final _cashFocus = FocusNode();
  bool _busy = false;
  String? _error;

  Store get store => widget.store;
  CartTotals get totals => store.cartTotals(widget.lines);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cashFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _cash.dispose();
    _card.dispose();
    _cashFocus.dispose();
    super.dispose();
  }

  double _parse(String text) {
    if (text.trim().isEmpty) return 0;
    return double.tryParse(text.replaceAll(',', '.')) ?? 0;
  }

  void _onCashChanged(String text) {
    final cash = _parse(text);
    final total = totals.total;
    if (text.trim().isEmpty) {
      _card.text = '';
    } else if (cash >= total) {
      _card.text = '0.00';
    } else {
      _card.text = (total - cash).toStringAsFixed(2);
    }
    setState(() => _error = null);
  }

  void _onCardChanged(String text) {
    final card = _parse(text);
    final total = totals.total;
    if (text.trim().isEmpty) {
      _cash.text = '';
    } else if (card >= total) {
      _cash.text = '0.00';
    } else {
      _cash.text = (total - card).toStringAsFixed(2);
    }
    setState(() => _error = null);
  }

  Future<void> _charge() async {
    if (_busy) return;
    final total = totals.total;
    final cash = _parse(_cash.text);
    final card = _parse(_card.text).clamp(0.0, total);
    var appliedCash = round2(total - card);
    if (cash > 0 && card == 0) appliedCash = total;
    final tendered = cash > 0 ? cash : appliedCash;
    if (tendered + card < total - 0.009) {
      setState(
        () => _error = 'Short by ${store.fmt(total - tendered - card)}.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sale = await store.completeSale(
        lines: widget.lines,
        card: card,
        cashTendered: tendered,
      );
      if (mounted) Navigator.of(context).pop(sale);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  List<double> get _quickCash {
    final total = totals.total;
    final values = <double>{
      total,
      (total / 10).ceilToDouble() * 10,
      50,
      100,
      200,
      500,
    }.where((v) => v >= total).toList()..sort();
    return values.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final total = totals.total;
    final cash = _parse(_cash.text);
    final card = _parse(_card.text).clamp(0.0, total);
    final change = cash > total
        ? round2(cash - total)
        : (cash > 0 && card == 0 ? round2(cash - total) : 0.0);
    final enough = cash + card >= total - 0.009 || (cash >= total);
    final short = total - cash - card;
    final onAccent = p.accent.computeLuminance() > 0.47
        ? const Color(0xFF08120F)
        : Colors.white;
    return SoraDialog(
      title: 'Take payment',
      subtitle:
          'Sale #${store.data.nextNumber} · ${numText(totals.items)} ${plural(totals.items, 'item')}',
      icon: Icons.payments_outlined,
      width: 650,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  p.accent.withValues(alpha: 0.13),
                  p.accent.withValues(alpha: 0.035),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: p.accent.withValues(alpha: 0.24)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AMOUNT DUE',
                      style: overlineStyle(p, color: p.accent),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      store.fmt(total),
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.8,
                        color: p.text,
                        height: 1,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Subtotal',
                      style: TextStyle(fontSize: 10.5, color: p.faint),
                    ),
                    Text(
                      store.fmt(totals.subtotal),
                      style: TextStyle(fontSize: 12, color: p.muted),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Tax',
                      style: TextStyle(fontSize: 10.5, color: p.faint),
                    ),
                    Text(
                      store.fmt(totals.tax),
                      style: TextStyle(fontSize: 12, color: p.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SoraField(
                  controller: _cash,
                  focusNode: _cashFocus,
                  label: 'Cash handed over',
                  hint: '0.00',
                  icon: Icons.payments_rounded,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: _onCashChanged,
                  onSubmitted: (_) => _charge(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SoraField(
                  controller: _card,
                  label: 'Card',
                  hint: '0.00',
                  icon: Icons.credit_card_rounded,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: _onCardChanged,
                  onSubmitted: (_) => _charge(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.call_split_rounded, size: 14, color: p.faint),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Cash and card can be split — type one amount and the other fills itself.',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: p.faint,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          if (cash > 0 && card > 0) ...[
            const SizedBox(height: 13),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 5,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: (cash / total * 1000)
                          .round()
                          .clamp(1, 999999)
                          .toInt(),
                      child: ColoredBox(color: p.accent),
                    ),
                    Expanded(
                      flex: (card / total * 1000)
                          .round()
                          .clamp(1, 999999)
                          .toInt(),
                      child: ColoredBox(color: p.accent2),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _PaymentLegend(
                  color: p.accent,
                  label: 'Cash ${store.fmt(cash)}',
                ),
                const Spacer(),
                _PaymentLegend(
                  color: p.accent2,
                  label: 'Card ${store.fmt(card)}',
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final value in _quickCash)
                FilterPill(
                  label: value == total ? 'Exact' : store.fmt(value),
                  selected: cash == value,
                  onTap: () {
                    _cash.text = value.toStringAsFixed(2);
                    _onCashChanged(_cash.text);
                    _cashFocus.requestFocus();
                  },
                ),
              FilterPill(
                label: 'Full amount on card',
                selected: card >= total && total > 0,
                onTap: () {
                  _card.text = total.toStringAsFixed(2);
                  _onCardChanged(_card.text);
                },
              ),
            ],
          ),
          if (change > 0) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.accent.withValues(alpha: 0.24)),
              ),
              child: Row(
                children: [
                  Icon(Icons.change_circle_outlined, size: 19, color: p.accent),
                  const SizedBox(width: 9),
                  Text(
                    'Change',
                    style: TextStyle(fontSize: 13, color: p.muted),
                  ),
                  const Spacer(),
                  Text(
                    store.fmt(change),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: p.accent,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(fontSize: 12, color: p.danger)),
          ] else if (!enough && (cash > 0 || card > 0)) ...[
            const SizedBox(height: 10),
            Text(
              'Short by ${store.fmt(short.abs())}',
              style: TextStyle(fontSize: 11.5, color: p.warning),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.keyboard_return_rounded, size: 13, color: p.faint),
              const SizedBox(width: 6),
              Text(
                'Press Enter to complete the sale',
                style: TextStyle(fontSize: 10.5, color: p.faint),
              ),
            ],
          ),
        ],
      ),
      actions: [
        GlassButton(
          label: 'Back',
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        GlassButton(
          label: enough
              ? 'Charge ${store.fmt(total)}'
              : (cash > 0 || card > 0)
              ? 'Short ${store.fmt(short.abs())}'
              : 'Enter an amount',
          icon: Icons.check_rounded,
          primary: true,
          loading: _busy,
          onPressed: enough ? _charge : null,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text('↵', style: TextStyle(fontSize: 9, color: onAccent)),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- holds

class _HeldSalesDialog extends StatefulWidget {
  final Store store;
  final CartController cart;
  final VoidCallback onResumed;
  const _HeldSalesDialog({
    required this.store,
    required this.cart,
    required this.onResumed,
  });

  @override
  State<_HeldSalesDialog> createState() => _HeldSalesDialogState();
}

class _HeldSalesDialogState extends State<_HeldSalesDialog> {
  late List<HeldSale> _holds = List.of(widget.store.data.holds);

  Future<void> _resume(HeldSale hold) async {
    if (widget.cart.lines.isNotEmpty) {
      await widget.store.holdSale(
        widget.cart.lines,
        label: 'Held before resuming',
      );
    }
    final lines = widget.store.resumeHold(hold.id);
    widget.cart.replace(lines);
    if (mounted) {
      Navigator.of(context).pop();
      widget.onResumed();
      showToast(context, 'Sale resumed.');
    }
  }

  Future<void> _discard(HeldSale hold) async {
    final confirmed = await showSoraDialog<bool>(
      context,
      maxWidth: 410,
      builder: (context) => SoraDialog(
        title: 'Throw this held sale away?',
        subtitle: 'It is written down in the day report, quietly.',
        icon: Icons.delete_outline_rounded,
        accent: context.palette.danger,
        child: const SizedBox.shrink(),
        actions: [
          GlassButton(
            label: 'Keep it',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          GlassButton(
            label: 'Throw away',
            danger: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.discardHold(hold.id);
    if (!mounted) return;
    setState(() => _holds = List.of(widget.store.data.holds));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SoraDialog(
      title: 'Held sales',
      subtitle: _holds.isEmpty
          ? 'Nothing is waiting.'
          : '${_holds.length} ${plural(_holds.length, 'sale')} waiting.',
      icon: Icons.pause_circle_outline_rounded,
      width: 650,
      child: _holds.isEmpty
          ? const EmptyState(
              icon: Icons.pause_circle_outline_rounded,
              title: 'No held sales',
              message: 'When someone steps away, hold the sale and serve the next customer.',
            )
          : Column(
              children: [
                for (final hold in _holds)
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
                            decoration: BoxDecoration(
                              color: p.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(
                              Icons.pause_rounded,
                              size: 17,
                              color: p.accent,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hold.label.isEmpty ? 'Held sale' : hold.label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: p.text,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${numText(hold.itemCount)} ${plural(hold.itemCount, 'item')} · ${widget.store.fmt(hold.total)} · ${timeShort(hold.at)} · ${hold.cashierName}',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: p.faint,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GlassButton(
                            label: 'Resume',
                            icon: Icons.play_arrow_rounded,
                            dense: true,
                            primary: true,
                            onPressed: () => _resume(hold),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: () => _discard(hold),
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              size: 17,
                              color: p.faint,
                            ),
                            splashRadius: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
      actions: [
        GlassButton(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
