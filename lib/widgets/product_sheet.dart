import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../store.dart';
import '../ui/kit.dart';
import '../ui/product_visual.dart';
import '../ui/theme.dart';

/// Opens the large product card from the till.
///
/// The sheet returns `true` when the person chose **Add to sale**, so the till
/// can keep its own add path (and its focus handling) in one place. It is a
/// fade-only route: the product mark itself carries the move with a hero, and
/// a scaling route around it would fight that flight.
Future<bool?> showProductSheet(
  BuildContext context,
  Store store,
  Product product,
) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.48),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (context, animation, secondaryAnimation) {
      return SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 760,
              maxHeight: MediaQuery.sizeOf(context).height * 0.86,
            ),
            child: _ProductSheet(store: store, product: product),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(opacity: curve, child: child);
    },
  );
}

class _ProductSheet extends StatelessWidget {
  final Store store;
  final Product product;
  const _ProductSheet({required this.store, required this.product});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final category = store.categoryName(product.categoryId);
    final tint = productTint(
      p,
      category.trim().isEmpty ? product.name : category,
    );
    final out = product.stock <= 0;
    final low = !out && product.stock <= store.data.shop.lowStock;
    final statusColor = out
        ? p.danger
        : low
        ? p.warning
        : p.success;
    final status = out
        ? 'OUT OF STOCK'
        : low
        ? 'LOW STOCK'
        : 'IN STOCK';

    Widget mark = ProductMark(
      name: product.name,
      category: category,
      size: 158,
    );
    if (!reduced) {
      mark = Hero(tag: productHeroTag(product), child: mark);
    }

    final facts = <Widget>[
      _Fact(label: 'SKU', value: product.sku.isEmpty ? '—' : product.sku),
      _Fact(
        label: 'Category',
        value: category.isEmpty ? 'Uncategorised' : category,
      ),
      _Fact(label: 'On the shelf', value: numText(product.stock)),
      if (store.isManagerOrOwner && product.cost > 0) ...[
        _Fact(label: 'Cost each', value: store.fmt(product.cost)),
        _Fact(
          label: 'Margin',
          value: product.price <= 0
              ? '—'
              : '${(((product.price - product.cost) / product.price) * 100).toStringAsFixed(0)}%',
        ),
        _Fact(label: 'Stock at cost', value: store.fmt(product.valueAtCost)),
      ],
      _Fact(label: 'Added', value: dateShort(product.createdAt)),
      _Fact(label: 'Last changed', value: dateShort(product.updatedAt)),
    ];

    return SoraDialog(
      title: product.name,
      subtitle: [
        if (category.isNotEmpty) category,
        if (product.sku.isNotEmpty) product.sku,
      ].join(' · '),
      icon: iconForCategory(category),
      accent: tint,
      width: 760,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              mark,
              const SizedBox(width: 26),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        StatusPill(
                          label: status,
                          color: statusColor,
                          icon: out
                              ? Icons.remove_circle_outline_rounded
                              : low
                              ? Icons.warning_amber_rounded
                              : Icons.check_rounded,
                        ),
                        if (store.isManagerOrOwner &&
                            product.price > 0 &&
                            product.cost > 0)
                          StatusPill(
                            label:
                                'MARGIN ${(((product.price - product.cost) / product.price) * 100).round()}%',
                            color: tint,
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      store.fmt(product.price),
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.2,
                        height: 1,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Retail price',
                      style: TextStyle(fontSize: 10.5, color: p.faint),
                    ),
                    const SizedBox(height: 20),
                    for (final fact in facts) fact,
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: p.matte ? 0.07 : 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tint.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Icon(Icons.touch_app_rounded, size: 15, color: tint),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Left-click a product to add it to the sale. Right-click '
                    'or hold it to open this card.',
                    style: TextStyle(fontSize: 11, color: p.muted, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        GlassButton(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        GlassButton(
          label: 'Add to sale',
          icon: Icons.add_rounded,
          primary: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

String productHeroTag(Product product) => 'product-mark-${product.id}';

class _Fact extends StatelessWidget {
  final String label;
  final String value;
  const _Fact({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.5),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: p.muted)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: p.text,
            ),
          ),
        ],
      ),
    );
  }
}
