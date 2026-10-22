import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../models.dart';
import '../store.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';

class StockScreen extends StatefulWidget {
  final Store store;
  const StockScreen({super.key, required this.store});

  @override
  State<StockScreen> createState() => StockScreenState();
}

class StockScreenState extends State<StockScreen> {
  final _filter = TextEditingController();
  final _filterFocus = FocusNode(debugLabel: 'Stock filter');
  Timer? _debounce;
  String _query = '';
  String _categoryId = '';
  bool _lowOnly = false;
  int _visible = 500;
  final Set<String> _selected = {};

  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _filterFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _filter.dispose();
    _filterFocus.dispose();
    super.dispose();
  }

  List<Product> get _products {
    final q = _query.trim().toLowerCase();
    final list = store.data.products.where((p) {
      if (_categoryId.isNotEmpty && p.categoryId != _categoryId) return false;
      if (_lowOnly && p.stock > store.data.shop.lowStock) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          p.searchName.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  void _onFilterChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      setState(() {
        _query = value;
        _visible = 500;
        _selected.clear();
      });
    });
  }

  void clearFilter() {
    _filter.clear();
    setState(() {
      _query = '';
      _categoryId = '';
      _lowOnly = false;
      _visible = 500;
      _selected.clear();
    });
    _filterFocus.requestFocus();
  }

  void _onFilterSubmitted(String value) {
    final match = store.exactMatch(value);
    if (match != null) {
      _edit(match);
    }
  }

  Future<void> startAdd() async {
    await _edit(null);
  }

  Future<void> _edit(Product? product) async {
    await showSoraDialog<void>(
      context,
      maxWidth: 600,
      builder: (context) => _ProductDialog(store: store, product: product),
    );
    if (mounted) {
      setState(() {});
      _filterFocus.requestFocus();
    }
  }

  Future<void> deleteTicked() async {
    if (_selected.isEmpty) {
      showToast(context, 'Tick the products to delete first.');
      return;
    }
    final p = context.palette;
    final confirmed = await showSoraDialog<bool>(
      context,
      maxWidth: 450,
      builder: (context) => SoraDialog(
        title: 'Delete ${_selected.length} ${plural(_selected.length, 'product')}?',
        subtitle: 'They leave the shelf and the till. Sales already recorded keep their own copy of the name and price.',
        icon: Icons.delete_outline_rounded,
        accent: p.danger,
        child: const SizedBox.shrink(),
        actions: [
          GlassButton(label: 'Keep them', onPressed: () => Navigator.of(context).pop(false)),
          GlassButton(label: 'Delete', icon: Icons.delete_outline_rounded, danger: true, onPressed: () => Navigator.of(context).pop(true)),
        ],
      ),
    );
    if (confirmed != true) return;
    await store.deleteProducts(_selected.toList());
    if (!mounted) return;
    setState(() => _selected.clear());
    showToast(context, 'Deleted.');
    _filterFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final products = _products;
    final shown = products.take(_visible).toList();
    final atCost = products.fold(0.0, (a, x) => a + x.valueAtCost);
    final atSell = products.fold(0.0, (a, x) => a + x.valueAtSell);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SoraField(
                controller: _filter,
                focusNode: _filterFocus,
                hint: 'Search or scan a product…',
                icon: Icons.search_rounded,
                onChanged: _onFilterChanged,
                onSubmitted: _onFilterSubmitted,
                suffix: _filter.text.isEmpty
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: GestureDetector(
                          onTap: clearFilter,
                          child: Icon(Icons.close_rounded, size: 15, color: p.faint),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 9),
            SoraSelect<String>(
              value: _categoryId,
              width: 172,
              icon: Icons.category_outlined,
              options: [
                const SoraSelectOption('', 'All categories'),
                for (final c in store.data.categories) SoraSelectOption(c.id, c.name),
              ],
              onChanged: (v) => setState(() {
                _categoryId = v;
                _visible = 500;
                _selected.clear();
              }),
            ),
            const SizedBox(width: 9),
            FilterPill(
              label: 'Low stock',
              icon: Icons.warning_amber_rounded,
              selected: _lowOnly,
              onTap: () => setState(() {
                _lowOnly = !_lowOnly;
                _visible = 500;
              }),
            ),
            const SizedBox(width: 9),
            GlassButton(
              label: 'Add product',
              icon: Icons.add_rounded,
              primary: true,
              onPressed: startAdd,
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(5)),
                child: Text('F12', style: TextStyle(fontSize: 8, color: p.accent.computeLuminance() > 0.55 ? const Color(0xFF08120F) : Colors.white)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              '${products.length} ${plural(products.length, 'product')}',
              style: TextStyle(fontSize: 11.5, color: p.muted, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 14),
            _MetricDot(label: 'at cost', value: store.fmt(atCost), color: p.muted),
            const SizedBox(width: 14),
            _MetricDot(label: 'at sell', value: store.fmt(atSell), color: p.accent),
            const Spacer(),
            if (_selected.isNotEmpty) ...[
              Text(
                '${_selected.length} ticked',
                style: TextStyle(fontSize: 11, color: p.danger, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              GlassButton(label: 'Delete selected', icon: Icons.delete_outline_rounded, danger: true, dense: true, onPressed: deleteTicked),
              const SizedBox(width: 6),
              GlassIconButton(icon: Icons.close_rounded, size: 34, tooltip: 'Clear selection', onPressed: () => setState(_selected.clear)),
            ] else
              Text('Click a row to edit', style: TextStyle(fontSize: 10.5, color: p.faint)),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: GlassPanel(
            blur: 20,
            radius: 20,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.hairline))),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 30,
                        child: Checkbox(
                          value: shown.isNotEmpty && shown.every((e) => _selected.contains(e.id)),
                          tristate: false,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selected.addAll(shown.map((e) => e.id));
                              } else {
                                _selected.removeAll(shown.map((e) => e.id));
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(flex: 4, child: _Head('Product', p)),
                      Expanded(flex: 2, child: _Head('SKU / barcode', p)),
                      Expanded(flex: 2, child: _Head('Category', p)),
                      Expanded(child: _Head('Price', p, align: TextAlign.right)),
                      Expanded(child: _Head('Cost', p, align: TextAlign.right)),
                      SizedBox(width: 78, child: _Head('Stock', p, align: TextAlign.right)),
                      const SizedBox(width: 28),
                    ],
                  ),
                ),
                Expanded(
                  child: shown.isEmpty
                      ? EmptyState(
                          icon: Icons.inventory_2_outlined,
                          title: 'No products here',
                          message: _query.isEmpty
                              ? 'Add the first product and it appears on the till straight away.'
                              : 'Nothing matches “$_query”.',
                          action: _query.isEmpty
                              ? GlassButton(label: 'Add product', icon: Icons.add_rounded, primary: true, onPressed: startAdd)
                              : GlassButton(label: 'Clear the filter', onPressed: clearFilter),
                        )
                      : Scrollbar(
                          child: ListView.builder(
                            itemCount: shown.length,
                            itemBuilder: (context, index) => _StockRow(
                              product: shown[index],
                              category: store.categoryName(shown[index].categoryId),
                              currency: store.currency,
                              lowStock: shown[index].stock <= store.data.shop.lowStock,
                              selected: _selected.contains(shown[index].id),
                              onSelected: (v) {
                                setState(() {
                                  if (v) {
                                    _selected.add(shown[index].id);
                                  } else {
                                    _selected.remove(shown[index].id);
                                  }
                                });
                              },
                              onTap: () => _edit(shown[index]),
                            ),
                          ),
                        ),
                ),
                if (shown.length < products.length)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: p.hairline))),
                    child: TextButton(
                      onPressed: () => setState(() => _visible += 500),
                      child: Text('Show more  ·  ${products.length - shown.length} still hidden'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricDot extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MetricDot({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Container(width: 5, height: 5, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$label ', style: TextStyle(fontSize: 10.5, color: p.faint)),
        Text(value, style: TextStyle(fontSize: 10.5, color: p.muted, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _Head extends StatelessWidget {
  final String text;
  final SoraPalette p;
  final TextAlign align;
  const _Head(this.text, this.p, {this.align = TextAlign.left});
  @override
  Widget build(BuildContext context) => Text(text, textAlign: align, style: overlineStyle(p));
}

class _StockRow extends StatefulWidget {
  final Product product;
  final String category;
  final String currency;
  final bool lowStock;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final VoidCallback onTap;

  const _StockRow({
    required this.product,
    required this.category,
    required this.currency,
    required this.lowStock,
    required this.selected,
    required this.onSelected,
    required this.onTap,
  });

  @override
  State<_StockRow> createState() => _StockRowState();
}

class _StockRowState extends State<_StockRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pr = widget.product;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: widget.selected
                ? p.accent.withValues(alpha: 0.07)
                : _hover
                    ? p.accent.withValues(alpha: 0.06)
                    : Colors.transparent,
            border: Border(bottom: BorderSide(color: p.hairline.withValues(alpha: 0.6))),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Checkbox(value: widget.selected, onChanged: (v) => widget.onSelected(v == true)),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        pr.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: p.text),
                      ),
                    ),
                    if (pr.cost <= 0) ...[
                      const SizedBox(width: 7),
                      Tooltip(message: 'No cost set — profit will read high', child: Icon(Icons.info_outline_rounded, size: 12, color: p.faint)),
                    ],
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  pr.sku.isEmpty ? '—' : pr.sku,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: p.faint, fontFamily: 'JetBrains Mono'),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(widget.category, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.muted)),
              ),
              Expanded(
                child: Text(
                  '${widget.currency}${moneyPlain(pr.price)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, color: p.text, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
              Expanded(
                child: Text(
                  '${widget.currency}${moneyPlain(pr.cost)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, color: p.muted, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
              SizedBox(
                width: 78,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: pr.stock <= 0
                          ? p.danger.withValues(alpha: 0.12)
                          : widget.lowStock
                              ? p.warning.withValues(alpha: 0.12)
                              : p.raised,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: pr.stock <= 0
                            ? p.danger.withValues(alpha: 0.3)
                            : widget.lowStock
                                ? p.warning.withValues(alpha: 0.3)
                                : p.hairline,
                      ),
                    ),
                    child: Text(
                      numText(pr.stock),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: pr.stock <= 0 ? p.danger : widget.lowStock ? p.warning : p.text,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Icon(Icons.chevron_right_rounded, size: 16, color: _hover ? p.accent : p.faint),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductDialog extends StatefulWidget {
  final Store store;
  final Product? product;
  const _ProductDialog({required this.store, this.product});

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _searchName;
  late final TextEditingController _price;
  late final TextEditingController _cost;
  late final TextEditingController _stock;
  final _nameFocus = FocusNode(debugLabel: 'Product name');
  late String _categoryId;
  bool _busy = false;
  String? _error;

  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p?.name ?? '');
    _sku = TextEditingController(text: p?.sku ?? '');
    _searchName = TextEditingController(text: p?.searchName ?? '');
    _price = TextEditingController(text: p == null ? '' : p.price.toStringAsFixed(2));
    _cost = TextEditingController(text: p == null ? '' : p.cost.toStringAsFixed(2));
    _stock = TextEditingController(text: p == null ? '0' : numText(p.stock));
    _categoryId = p?.categoryId ??
        (store.data.categories.isNotEmpty ? store.data.categories.first.id : '');
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _searchName.dispose();
    _price.dispose();
    _cost.dispose();
    _stock.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the product a name.');
      return;
    }
    final price = double.tryParse(_price.text.replaceAll(',', '.'));
    final cost = double.tryParse(_cost.text.replaceAll(',', '.')) ?? 0;
    final stock = double.tryParse(_stock.text.replaceAll(',', '.'));
    if (price == null || price < 0) {
      setState(() => _error = 'Give it a price.');
      return;
    }
    if (stock == null) {
      setState(() => _error = 'The stock count must be a number.');
      return;
    }
    final sku = _sku.text.trim();
    if (sku.isNotEmpty &&
        store.data.products.any((p) => p.id != widget.product?.id && p.sku.isNotEmpty && p.sku.toLowerCase() == sku.toLowerCase())) {
      setState(() => _error = 'Another product already uses that SKU / barcode.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final product = widget.product?.copyWith(
          name: name,
          sku: sku,
          searchName: _searchName.text.trim(),
          categoryId: _categoryId,
          price: round2(price),
          cost: round2(cost),
          stock: stock,
        ) ??
        Product(
          id: newId(),
          name: name,
          sku: sku,
          searchName: _searchName.text.trim(),
          categoryId: _categoryId,
          price: round2(price),
          cost: round2(cost),
          stock: stock,
        );
    await store.upsertProduct(product);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final p = context.palette;
    final confirmed = await showSoraDialog<bool>(
      context,
      maxWidth: 420,
      builder: (context) => SoraDialog(
        title: 'Delete ${widget.product!.name}?',
        subtitle: 'Sales already recorded are not touched.',
        icon: Icons.delete_outline_rounded,
        accent: p.danger,
        child: const SizedBox.shrink(),
        actions: [
          GlassButton(label: 'Keep it', onPressed: () => Navigator.of(context).pop(false)),
          GlassButton(label: 'Delete', danger: true, onPressed: () => Navigator.of(context).pop(true)),
        ],
      ),
    );
    if (confirmed != true) return;
    await store.deleteProduct(widget.product!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final editing = widget.product != null;
    return SoraDialog(
      title: editing ? 'Edit product' : 'Add a product',
      subtitle: editing ? 'Changes to stock and price are written quietly into the day report.' : 'It appears on the till as soon as you save.',
      icon: editing ? Icons.edit_rounded : Icons.add_box_outlined,
      width: 600,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SoraField(
            controller: _name,
            focusNode: _nameFocus,
            label: 'Name',
            hint: 'e.g. Butter Croissant',
            icon: Icons.label_outline_rounded,
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SoraField(
                  controller: _sku,
                  autofocus: true,
                  label: 'SKU / barcode',
                  hint: 'Scan here — or type it',
                  icon: Icons.qr_code_2_rounded,
                  onSubmitted: (_) => _nameFocus.requestFocus(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SoraField(
                  controller: _searchName,
                  label: 'Search name (optional)',
                  hint: 'e.g. mp',
                  icon: Icons.short_text_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SoraSelect<String>(
            label: 'Category',
            value: _categoryId,
            icon: Icons.category_outlined,
            options: store.data.categories.isEmpty
                ? const [SoraSelectOption('', 'Uncategorised')]
                : store.data.categories.map((c) => SoraSelectOption(c.id, c.name)).toList(),
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SoraField(
                  controller: _price,
                  label: 'Sell price',
                  hint: '0.00',
                  prefix: _CurrencyPrefix(symbol: store.currency),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SoraField(
                  controller: _cost,
                  label: 'Cost',
                  hint: '0.00',
                  prefix: _CurrencyPrefix(symbol: store.currency),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SoraField(
                  controller: _stock,
                  label: 'On the shelf',
                  hint: '0',
                  icon: Icons.inventory_rounded,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onSubmitted: (_) => _save(),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(fontSize: 12, color: p.danger)),
          ],
          if (editing) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                GlassButton(label: 'Delete', icon: Icons.delete_outline_rounded, danger: true, dense: true, onPressed: _delete),
                const Spacer(),
                Text(
                  'Created ${dateMedium(widget.product!.createdAt)}',
                  style: TextStyle(fontSize: 10, color: p.faint),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        GlassButton(label: 'Cancel', onPressed: _busy ? null : () => Navigator.of(context).pop()),
        GlassButton(
          label: editing ? 'Save changes' : 'Add product',
          icon: Icons.check_rounded,
          primary: true,
          loading: _busy,
          onPressed: _save,
        ),
      ],
    );
  }
}

class _CurrencyPrefix extends StatelessWidget {
  final String symbol;
  const _CurrencyPrefix({required this.symbol});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 7),
      child: Text(symbol, style: TextStyle(fontSize: 13, color: p.muted, fontWeight: FontWeight.w600)),
    );
  }
}
