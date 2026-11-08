import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_theme.dart';
import 'models/product.dart';
import 'repositories/inventory_repository.dart';
import 'services/product_image_storage_service.dart';
import 'stocktake_screen.dart';

/// Functional, offline-first product and stock screen.
///
/// actorUserId and deviceId must eventually come from the authenticated
/// session and registered-device services. The current app shell supplies
/// clearly marked local-development identifiers until those services exist.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    required this.actorUserId,
    required this.deviceId,
    InventoryRepository? repository,
  }) : _repository = repository;

  final String actorUserId;
  final String deviceId;
  final InventoryRepository? _repository;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late final InventoryRepository _repository =
      widget._repository ?? InventoryRepository();

  final ProductImageStorageService _imageStorage = ProductImageStorageService();

  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _money =
      NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 2);

  List<Product> _products = [];
  Map<String, double> _balances = {};
  bool _loading = true;
  String _search = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final products = await _repository.getProducts(search: _search);
      final balances = await _repository.getStockBalances();
      if (!mounted) return;
      setState(() {
        _products = products;
        _balances = balances;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _message(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
      ),
    );
  }

  double _number(String value, String field) {
    final parsed = double.tryParse(value.trim());
    if (parsed == null || !parsed.isFinite) {
      throw FormatException('$field must be a valid number.');
    }
    return parsed;
  }

  Future<void> _addProduct() async {
    final name = TextEditingController();
    final code = TextEditingController();
    final category = TextEditingController();
    final description = TextEditingController();
    final baseUnit = TextEditingController(text: 'piece');
    final buying = TextEditingController(text: '0');
    final selling = TextEditingController(text: '0');
    final minimum = TextEditingController(text: '0');
    final opening = TextEditingController(text: '0');
    final formKey = GlobalKey<FormState>();
    String? selectedImagePath;
    File? selectedImageFile;
    bool saved = false;

    try {
      final values = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Add product'),
            content: SizedBox(
              width: 480,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _imagePickerSection(
                        selectedImageFile,
                        onPick: () async {
                          try {
                            final path =
                                await _imageStorage.pickAndStoreImage();
                            if (path == null) return;
                            final file =
                                await _imageStorage.resolveImageFile(path);
                            if (file == null) {
                              await _imageStorage.deleteImage(path);
                              throw StateError(
                                  'The selected image could not be opened.');
                            }
                            setDialogState(() {
                              selectedImagePath = path;
                              selectedImageFile = file;
                            });
                          } catch (error) {
                            _message('Could not select image: $error',
                                isError: true);
                          }
                        },
                        onRemove: selectedImagePath == null
                            ? null
                            : () {
                                final oldPath = selectedImagePath;
                                setDialogState(() {
                                  selectedImagePath = null;
                                  selectedImageFile = null;
                                });
                                if (oldPath != null) {
                                  _imageStorage.deleteImage(oldPath);
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      _field(name, 'Product name', requiredField: true),
                      _field(code, 'Product code / barcode'),
                      _field(category, 'Category'),
                      _field(description, 'Description', maxLines: 2),
                      _field(baseUnit, 'Base unit (e.g. piece)',
                          requiredField: true),
                      _field(buying, 'Buying cost per base unit (KES)',
                          numeric: true),
                      _field(selling, 'Selling price per base unit (KES)',
                          numeric: true),
                      _field(minimum, 'Minimum stock level (base units)',
                          numeric: true),
                      _field(opening, 'Opening stock (base units)',
                          numeric: true),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(dialogContext, {
                      'name': name.text,
                      'code': code.text,
                      'category': category.text,
                      'description': description.text,
                      'baseUnit': baseUnit.text,
                      'buying': buying.text,
                      'selling': selling.text,
                      'minimum': minimum.text,
                      'opening': opening.text,
                    });
                  }
                },
                child: const Text('Save product'),
              ),
            ],
          ),
        ),
      );

      if (values == null) return;
      final buyingMinor =
          (_number(values['buying']!, 'Buying cost') * 100).round();
      final sellingMinor =
          (_number(values['selling']!, 'Selling price') * 100).round();
      final minimumQuantity = _number(values['minimum']!, 'Minimum stock');
      final openingQuantity = _number(values['opening']!, 'Opening stock');

      if (buyingMinor < 0 ||
          sellingMinor < 0 ||
          minimumQuantity < 0 ||
          openingQuantity < 0) {
        throw FormatException('Prices and quantities cannot be negative.');
      }

      await _repository.createProduct(
        name: values['name']!,
        code: values['code']!.trim().isEmpty ? null : values['code']!.trim(),
        category: values['category']!.trim().isEmpty
            ? null
            : values['category']!.trim(),
        description: values['description']!.trim().isEmpty
            ? null
            : values['description']!.trim(),
        baseUnit: values['baseUnit']!,
        buyingCostMinor: buyingMinor,
        sellingPriceMinor: sellingMinor,
        minimumQuantity: minimumQuantity,
        openingQuantity: openingQuantity,
        imagePath: selectedImagePath,
        actorUserId: widget.actorUserId,
        deviceId: widget.deviceId,
      );
      saved = true;
      _message('Product saved successfully.');
      await _loadProducts();
    } catch (error) {
      _message(error.toString(), isError: true);
    } finally {
      if (!saved && selectedImagePath != null) {
        await _imageStorage.deleteImage(selectedImagePath);
      }
      name.dispose();
      code.dispose();
      category.dispose();
      description.dispose();
      baseUnit.dispose();
      buying.dispose();
      selling.dispose();
      minimum.dispose();
      opening.dispose();
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool requiredField = false,
    bool numeric = false,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(labelText: label),
        validator: requiredField
            ? (value) => value == null || value.trim().isEmpty
                ? 'This field is required.'
                : null
            : null,
      ),
    );
  }

  Future<void> _editProduct(Product product) async {
    final name = TextEditingController(text: product.name);
    final code = TextEditingController(text: product.code ?? '');
    final category = TextEditingController(text: product.category ?? '');
    final description = TextEditingController(text: product.description ?? '');
    final selling = TextEditingController(
      text: (product.sellingPriceMinor / 100).toStringAsFixed(2),
    );
    final minimum =
        TextEditingController(text: product.minimumQuantity.toString());
    final formKey = GlobalKey<FormState>();
    final originalImagePath = product.imagePath;
    String? selectedImagePath = originalImagePath;
    File? selectedImageFile;
    final newlyStoredPaths = <String>[];
    bool saved = false;

    try {
      selectedImageFile =
          await _imageStorage.resolveImageFile(originalImagePath);
      if (!mounted) return;
      final values = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Edit product — ${product.name}'),
            content: SizedBox(
              width: 460,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _imagePickerSection(
                        selectedImageFile,
                        onPick: () async {
                          try {
                            final path =
                                await _imageStorage.pickAndStoreImage();
                            if (path == null) return;
                            final file =
                                await _imageStorage.resolveImageFile(path);
                            if (file == null) {
                              await _imageStorage.deleteImage(path);
                              throw StateError(
                                  'The selected image could not be opened.');
                            }
                            newlyStoredPaths.add(path);
                            setDialogState(() {
                              selectedImagePath = path;
                              selectedImageFile = file;
                            });
                          } catch (error) {
                            _message('Could not select image: $error',
                                isError: true);
                          }
                        },
                        onRemove: null,
                      ),
                      const SizedBox(height: 12),
                      _field(name, 'Product name', requiredField: true),
                      _field(code, 'Product code'),
                      _field(category, 'Category'),
                      _field(description, 'Description', maxLines: 2),
                      _field(selling, 'Selling price (KES)', numeric: true),
                      _field(
                          minimum, 'Minimum stock level (${product.baseUnit})',
                          numeric: true),
                      const SizedBox(height: 6),
                      Text(
                        'Buying cost: ${_money.format(product.buyingCostMinor / 100)}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Buying cost is maintained through stock receiving.',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(dialogContext, {
                      'name': name.text,
                      'code': code.text,
                      'category': category.text,
                      'description': description.text,
                      'selling': selling.text,
                      'minimum': minimum.text,
                    });
                  }
                },
                child: const Text('Save changes'),
              ),
            ],
          ),
        ),
      );

      if (values == null) return;
      final sellingMinor =
          (_number(values['selling']!, 'Selling price') * 100).round();
      final minimumQuantity = _number(values['minimum']!, 'Minimum stock');
      if (sellingMinor < 0 || minimumQuantity < 0) {
        throw FormatException('Prices and quantities cannot be negative.');
      }

      await _repository.updateProduct(
        productId: product.id,
        name: values['name']!,
        code: values['code']!,
        category: values['category']!,
        description: values['description']!,
        buyingCostMinor: product.buyingCostMinor,
        sellingPriceMinor: sellingMinor,
        minimumQuantity: minimumQuantity,
        imagePath: selectedImagePath,
        actorUserId: widget.actorUserId,
        deviceId: widget.deviceId,
      );
      saved = true;

      if (originalImagePath != null && originalImagePath != selectedImagePath) {
        await _imageStorage.deleteImage(originalImagePath);
      }
      for (final path in newlyStoredPaths) {
        if (path != selectedImagePath) await _imageStorage.deleteImage(path);
      }

      _message('Product updated successfully.');
      await _loadProducts();
    } catch (error) {
      _message(error.toString(), isError: true);
    } finally {
      if (!saved) {
        for (final path in newlyStoredPaths) {
          await _imageStorage.deleteImage(path);
        }
      }
      name.dispose();
      code.dispose();
      category.dispose();
      description.dispose();
      selling.dispose();
      minimum.dispose();
    }
  }

  Widget _imagePickerSection(
    File? imageFile, {
    required VoidCallback onPick,
    VoidCallback? onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Product photo',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: imageFile == null
                  ? Icon(
                      Icons.add_a_photo_outlined,
                      size: 32,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )
                  : Image.file(
                      imageFile,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.broken_image_outlined,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    onPressed: onPick,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(
                        imageFile == null ? 'Choose photo' : 'Replace photo'),
                  ),
                  if (onRemove != null)
                    TextButton.icon(
                      onPressed: onRemove,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove photo'),
                    ),
                  Text(
                    'Stored on this device for offline use.',
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _manageUnits(Product product) async {
    final units = await _repository.getProductUnits(product.id);
    if (!mounted) return;

    final unitName = TextEditingController();
    final factor = TextEditingController(text: '1');
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Units — ${product.name}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'Configured units and their conversion to the base unit.'),
                const SizedBox(height: 12),
                ...units.map((unit) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(unit.unitName),
                      trailing: Text(
                        '${unit.baseUnitsPerUnit} ${product.baseUnit}',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    )),
                const Divider(),
                TextField(
                  controller: unitName,
                  decoration: const InputDecoration(
                    labelText: 'New unit name (e.g. box)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: factor,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Base units in one ${product.baseUnit}',
                    helperText: 'Example: 1 box = 24 pieces, enter 24',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Add unit'),
            ),
          ],
        ),
      ),
    );

    try {
      if (result != true) return;
      await _repository.addProductUnit(
        productId: product.id,
        unitName: unitName.text,
        baseUnitsPerUnit: _number(factor.text, 'Conversion factor'),
        actorUserId: widget.actorUserId,
        deviceId: widget.deviceId,
      );
      _message('Unit added.');
      await _loadProducts();
    } catch (error) {
      _message(error.toString(), isError: true);
    } finally {
      unitName.dispose();
      factor.dispose();
    }
  }

  Future<void> _recordMovement(Product product, String movementType) async {
    final units = await _repository.getProductUnits(product.id);
    if (!mounted) return;
    if (units.isEmpty) {
      _message('This product has no configured units.', isError: true);
      return;
    }

    final quantity = TextEditingController();
    final reason = TextEditingController();
    String selectedUnit = product.baseUnit;

    final needsReason = {
      'damage',
      'expiry',
      'adjustment_in',
      'adjustment_out',
    }.contains(movementType);

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_movementTitle(movementType)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Product: ${product.name}'),
                const SizedBox(height: 12),
                TextField(
                  controller: quantity,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: units.any((u) => u.unitName == selectedUnit)
                      ? selectedUnit
                      : units.first.unitName,
                  decoration: const InputDecoration(labelText: 'Unit'),
                  items: units
                      .map((unit) => DropdownMenuItem(
                            value: unit.unitName,
                            child: Text(
                              '${unit.unitName} (${unit.baseUnitsPerUnit} ${product.baseUnit})',
                            ),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedUnit = value);
                    }
                  },
                ),
                if (needsReason) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: reason,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Reason (required)',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Record movement'),
            ),
          ],
        ),
      ),
    );

    try {
      if (result != true) return;
      await _repository.recordStockMovement(
        productId: product.id,
        movementType: movementType,
        quantity: _number(quantity.text, 'Quantity'),
        unitName: selectedUnit,
        actorUserId: widget.actorUserId,
        deviceId: widget.deviceId,
        reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
      );
      _message('${_movementTitle(movementType)} recorded.');
      await _loadProducts();
    } catch (error) {
      _message(error.toString(), isError: true);
    } finally {
      quantity.dispose();
      reason.dispose();
    }
  }

  String _movementTitle(String type) {
    switch (type) {
      case 'receipt':
        return 'Receive stock';
      case 'damage':
        return 'Record damaged stock';
      case 'expiry':
        return 'Record expired stock';
      case 'adjustment_in':
        return 'Increase stock (adjustment)';
      case 'adjustment_out':
        return 'Reduce stock (adjustment)';
      case 'return_in':
        return 'Record customer return';
      case 'return_out':
        return 'Record supplier return';
      default:
        return 'Stock movement';
    }
  }

  Future<void> _archive(Product product) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive product?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                'Archive ${product.name}? Products with remaining stock cannot be archived.'),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Archive reason'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    try {
      if (confirmed != true) return;
      await _repository.archiveProduct(
        productId: product.id,
        actorUserId: widget.actorUserId,
        deviceId: widget.deviceId,
        reason: reason.text,
      );
      _message('Product archived.');
      await _loadProducts();
    } catch (error) {
      _message(error.toString(), isError: true);
    } finally {
      reason.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lowStockCount = _products
        .where((p) => (_balances[p.id] ?? 0) <= p.minimumQuantity)
        .length;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadProducts,
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 12,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Products & stock',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Manage your catalogue, units and stock movements.',
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => StocktakeScreen(
                              actorUserId: widget.actorUserId,
                              deviceId: widget.deviceId,
                            ),
                          ),
                        );
                        await _loadProducts();
                      },
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Stocktake'),
                    ),
                    FilledButton.icon(
                      onPressed: _addProduct,
                      icon: const Icon(Icons.add),
                      label: const Text('Add product'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _summaryCard(
                  'Active products',
                  '${_products.length}',
                  Icons.inventory_2_outlined,
                  AppTheme.navy,
                ),
                _summaryCard(
                  'Low stock',
                  '$lowStockCount',
                  Icons.warning_amber_outlined,
                  AppTheme.amber,
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _searchController,
              onChanged: (value) {
                _search = value;
                _loadProducts();
              },
              decoration: InputDecoration(
                hintText: 'Search by product name or code',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    _search = '';
                    _loadProducts();
                  },
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(36),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Text(_error!, style: TextStyle(color: AppTheme.danger)),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: _loadProducts,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_products.isEmpty)
              Card(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Column(
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 42,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                      SizedBox(height: 10),
                      Text(
                        'No products found',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface),
                      ),
                      SizedBox(height: 4),
                      Text('Add your first product or change your search.'),
                    ],
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 12.0;
                  const minimumCardWidth = 280.0;

                  final columns = (constraints.maxWidth / minimumCardWidth)
                      .floor()
                      .clamp(2, 6);
                  final double cardWidth =
                      (constraints.maxWidth - (spacing * (columns - 1))) /
                          columns;

                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: _products.map((product) {
                      return SizedBox(
                        width: cardWidth,
                        child: _productCard(product),
                      );
                    }).toList(),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Icon(icon, color: color, size: 27),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      )),
                  Text(title,
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _productThumbnail(Product product) {
    final theme = Theme.of(context);

    return FutureBuilder<File?>(
      future: _imageStorage.resolveImageFile(product.imagePath),
      builder: (context, snapshot) {
        final file = snapshot.data;

        return Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: file == null
              ? Icon(
                  Icons.inventory_2_outlined,
                  size: 23,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : Image.file(
                  file,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.inventory_2_outlined,
                    size: 23,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
        );
      },
    );
  }

  Widget _productCard(Product product) {
    final balance = _balances[product.id] ?? 0;
    final low = balance <= product.minimumQuantity;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _productThumbnail(product),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(product.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                )),
                            const SizedBox(height: 3),
                            Text(
                                [
                                  if (product.code != null &&
                                      product.code!.isNotEmpty)
                                    'Code: ${product.code}',
                                  if (product.category != null &&
                                      product.category!.isNotEmpty)
                                    product.category!,
                                ].join(' • ').isEmpty
                                    ? 'No code or category'
                                    : [
                                        if (product.code != null &&
                                            product.code!.isNotEmpty)
                                          'Code: ${product.code}',
                                        if (product.category != null &&
                                            product.category!.isNotEmpty)
                                          product.category!,
                                      ].join(' • '),
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontSize: 11,
                                )),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Chip(
                  avatar: Icon(
                    low ? Icons.warning_amber : Icons.check_circle_outline,
                    size: 17,
                    color: low
                        ? (Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFFFFC266)
                            : AppTheme.amber)
                        : Theme.of(context).colorScheme.secondary,
                  ),
                  label: Text(
                    low ? 'Low stock' : 'In stock',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ],
            ),
            const Divider(height: 22),
            Wrap(
              spacing: 24,
              runSpacing: 10,
              children: [
                _detail(
                    'Available', '${_quantity(balance)} ${product.baseUnit}'),
                _detail('Minimum',
                    '${_quantity(product.minimumQuantity)} ${product.baseUnit}'),
                _detail('Buying', _money.format(product.buyingCostMinor / 100)),
                _detail(
                    'Selling', _money.format(product.sellingPriceMinor / 100)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                IconButton(
                  tooltip: 'Edit product',
                  onPressed: () => _editProduct(product),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Receive stock',
                  onPressed: () => _recordMovement(product, 'receipt'),
                  icon: const Icon(Icons.add_box_outlined),
                ),
                IconButton(
                  tooltip: 'Stock adjustment',
                  onPressed: () => _recordMovement(product, 'adjustment_out'),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                IconButton(
                  tooltip: 'Manage units',
                  onPressed: () => _manageUnits(product),
                  icon: const Icon(Icons.straighten),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More stock actions',
                  onSelected: (value) => _recordMovement(product, value),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                        value: 'damage', child: Text('Record damage')),
                    PopupMenuItem(
                        value: 'expiry', child: Text('Record expiry')),
                    PopupMenuItem(
                        value: 'return_in', child: Text('Customer return')),
                    PopupMenuItem(
                        value: 'return_out', child: Text('Supplier return')),
                    PopupMenuItem(
                        value: 'adjustment_in', child: Text('Increase stock')),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.more_horiz),
                  ),
                ),
                IconButton(
                  tooltip: 'Archive product',
                  onPressed: () => _archive(product),
                  icon: const Icon(Icons.archive_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String value) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  String _quantity(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
