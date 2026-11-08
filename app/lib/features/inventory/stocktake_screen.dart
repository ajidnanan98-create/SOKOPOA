import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import 'models/product.dart';
import 'models/product_unit.dart';
import 'repositories/inventory_repository.dart';
import 'repositories/stocktake_repository.dart';

class StocktakeScreen extends StatefulWidget {
  const StocktakeScreen({
    super.key,
    required this.actorUserId,
    required this.deviceId,
  });

  final String actorUserId;
  final String deviceId;

  @override
  State<StocktakeScreen> createState() => _StocktakeScreenState();
}

class _StocktakeScreenState extends State<StocktakeScreen> {
  final InventoryRepository _inventoryRepository = InventoryRepository();
  final StocktakeRepository _stocktakeRepository = StocktakeRepository();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _lineReasonController = TextEditingController();

  List<Product> _products = [];
  Map<String, double> _balances = {};
  List<Map<String, dynamic>> _lines = [];
  List<Map<String, dynamic>> _sessions = [];
  List<ProductUnit> _units = [];

  Product? _selectedProduct;
  String? _selectedUnitName;
  Map<String, dynamic>? _activeSession;

  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _lineReasonController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await _inventoryRepository.getProducts();
      final balances = await _inventoryRepository.getStockBalances();
      final sessions = await _stocktakeRepository.getStocktakes();
      final draft = sessions.cast<Map<String, dynamic>?>().firstWhere(
            (session) => session?['status'] == 'draft',
            orElse: () => null,
          );

      if (!mounted) return;
      setState(() {
        _products = products;
        _balances = balances;
        _sessions = sessions;
        _activeSession = draft;
        _loading = false;
      });
      if (draft != null) {
        await _loadLines(draft['id'] as String);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadLines(String stocktakeId) async {
    final lines = await _stocktakeRepository.getStocktakeLines(stocktakeId);
    if (!mounted) return;
    setState(() => _lines = lines);
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.danger : AppTheme.navy,
      ),
    );
  }

  Future<void> _startStocktake() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start stocktake'),
        content: TextField(
          controller: reasonController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Session note (optional)',
            hintText: 'e.g. Monthly physical stock count',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Start'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      reasonController.dispose();
      return;
    }

    setState(() => _busy = true);
    try {
      final session = await _stocktakeRepository.startStocktake(
        actorUserId: widget.actorUserId,
        deviceId: widget.deviceId,
        reason: reasonController.text,
      );
      if (!mounted) return;
      setState(() {
        _activeSession = session;
        _lines = [];
        _sessions = [session, ..._sessions];
        _selectedProduct = null;
        _units = [];
        _selectedUnitName = null;
        _quantityController.clear();
        _lineReasonController.clear();
      });
      _showMessage('Stocktake started.');
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    } finally {
      reasonController.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectProduct(String? productId) async {
    Product? product;

    for (final item in _products) {
      if (item.id == productId) {
        product = item;
        break;
      }
    }

    if (product == null) return;

    // The null check above guarantees that this is a valid Product.
    final selectedProduct = product;

    setState(() {
      _selectedProduct = selectedProduct;
      _units = [];
      _selectedUnitName = null;
      _quantityController.clear();
      _lineReasonController.clear();
    });

    try {
      final units = await _inventoryRepository.getProductUnits(
        selectedProduct.id,
      );

      if (!mounted) return;

      setState(() {
        _units = units;

        final baseUnitExists = units.any(
          (unit) =>
              unit.unitName.toLowerCase() ==
              selectedProduct.baseUnit.toLowerCase(),
        );

        if (baseUnitExists) {
          _selectedUnitName = units
              .firstWhere(
                (unit) =>
                    unit.unitName.toLowerCase() ==
                    selectedProduct.baseUnit.toLowerCase(),
              )
              .unitName;
        } else if (units.isNotEmpty) {
          _selectedUnitName = units.first.unitName;
        }
      });
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    }
  }

  Future<void> _saveCount() async {
    final session = _activeSession;
    final product = _selectedProduct;
    final unitName = _selectedUnitName;
    final quantity = double.tryParse(_quantityController.text.trim());

    if (session == null || product == null || unitName == null) {
      _showMessage('Select a product and a counting unit.', isError: true);
      return;
    }
    if (quantity == null || !quantity.isFinite || quantity < 0) {
      _showMessage('Enter a valid quantity of zero or greater.', isError: true);
      return;
    }

    setState(() => _busy = true);
    try {
      await _stocktakeRepository.recordCount(
        stocktakeId: session['id'] as String,
        productId: product.id,
        enteredQuantity: quantity,
        unitName: unitName,
        reason: _lineReasonController.text,
      );
      await _loadLines(session['id'] as String);
      _quantityController.clear();
      _lineReasonController.clear();
      _showMessage('Count saved for ${product.name}.');
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finalizeStocktake() async {
    final session = _activeSession;
    if (session == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Finalize stocktake?'),
        content: const Text(
          'This will record the counted stock differences as stock adjustments. '
          'The completed stocktake cannot be edited.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Review first'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Finalize'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await _stocktakeRepository.finalizeStocktake(
        stocktakeId: session['id'] as String,
      );
      if (!mounted) return;
      _showMessage('Stocktake finalized. Verified adjustments were recorded.');
      setState(() {
        _activeSession = null;
        _lines = [];
        _selectedProduct = null;
        _units = [];
        _selectedUnitName = null;
      });
      await _loadInitialData();
    } catch (error) {
      _showMessage(error.toString(), isError: true);
      await _loadLines(session['id'] as String);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelStocktake() async {
    final session = _activeSession;
    if (session == null) return;

    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel stocktake'),
        content: TextField(
          controller: reasonController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Cancellation reason',
            hintText: 'Explain why this count is being cancelled',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep draft'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel stocktake'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      reasonController.dispose();
      return;
    }

    setState(() => _busy = true);
    try {
      await _stocktakeRepository.cancelStocktake(
        stocktakeId: session['id'] as String,
        reason: reasonController.text,
      );
      if (!mounted) return;
      _showMessage('Stocktake cancelled.');
      setState(() {
        _activeSession = null;
        _lines = [];
      });
      await _loadInitialData();
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    } finally {
      reasonController.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  String _quantity(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final session = _activeSession;
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadInitialData,
              child: ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: 12,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Stocktake',
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.navy,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Count physical stock and review differences before adjusting inventory.',
                            style: TextStyle(color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                      if (session == null)
                        FilledButton.icon(
                          onPressed: _busy ? null : _startStocktake,
                          icon: const Icon(Icons.playlist_add_check),
                          label: const Text('Start stocktake'),
                        )
                      else
                        Chip(
                          avatar: const Icon(Icons.edit_note, size: 18),
                          label: Text('Draft Ã‚Â· ${_lines.length} counted'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: AppTheme.danger),
                        ),
                      ),
                    ),
                  if (session == null)
                    _emptyOrHistory()
                  else ...[
                    _sessionSummary(session),
                    const SizedBox(height: 14),
                    _countEntryCard(),
                    const SizedBox(height: 18),
                    _reviewCard(),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _cancelStocktake,
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Cancel draft'),
                        ),
                        FilledButton.icon(
                          onPressed: _busy || _lines.isEmpty
                              ? null
                              : _finalizeStocktake,
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Finalize stocktake'),
                        ),
                      ],
                    ),
                  ],
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _emptyOrHistory() {
    final recent = _sessions.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              children: const [
                Icon(Icons.fact_check_outlined,
                    size: 42, color: AppTheme.textMuted),
                SizedBox(height: 10),
                Text(
                  'No active stocktake',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.navy,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Start a stocktake when you are ready to compare physical quantities with recorded stock.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
        ),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text(
            'Recent stocktakes',
            style: TextStyle(
              color: AppTheme.navy,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          ...recent.map((item) {
            final status = (item['status'] as String?) ?? 'unknown';
            final started = (item['started_at'] as String?) ?? '';
            return Card(
              child: ListTile(
                leading: Icon(
                  status == 'completed'
                      ? Icons.check_circle_outline
                      : status == 'cancelled'
                          ? Icons.cancel_outlined
                          : Icons.pending_outlined,
                  color: status == 'completed'
                      ? Colors.green
                      : status == 'cancelled'
                          ? AppTheme.textMuted
                          : AppTheme.amber,
                ),
                title: Text('Stocktake Ã‚Â· $status'),
                subtitle: Text(started.isEmpty ? 'Date unavailable' : started),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _sessionSummary(Map<String, dynamic> session) {
    final reason = (session['reason'] as String?)?.trim();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.assignment_outlined, color: AppTheme.navy),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Active draft',
                    style: TextStyle(
                      color: AppTheme.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    reason == null || reason.isEmpty
                        ? 'No session note'
                        : reason,
                    style: const TextStyle(color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            Text(
              '${_lines.length} products counted',
              style: const TextStyle(
                color: AppTheme.navy,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countEntryCard() {
    final product = _selectedProduct;
    final systemBalance =
        product == null ? 0.0 : (_balances[product.id] ?? 0.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Record physical count',
              style: TextStyle(
                color: AppTheme.navy,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: product?.id,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Product'),
              items: _products
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item.id,
                      child: Text(
                        item.code == null || item.code!.isEmpty
                            ? item.name
                            : '${item.name} (${item.code})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _busy ? null : _selectProduct,
            ),
            if (product != null) ...[
              const SizedBox(height: 10),
              Text(
                'Recorded stock: ${_quantity(systemBalance)} ${product.baseUnit}',
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _quantityController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Physical quantity',
                        hintText: 'Enter counted amount',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedUnitName,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: _units
                          .map(
                            (unit) => DropdownMenuItem<String>(
                              value: unit.unitName,
                              child: Text(
                                unit.unitName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (value) =>
                              setState(() => _selectedUnitName = value),
                    ),
                  ),
                ],
              ),
              if (_units.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'No units are configured for this product. Configure its units before counting.',
                    style: TextStyle(color: AppTheme.danger),
                  ),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: _lineReasonController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Discrepancy reason (required if stock differs)',
                  hintText: 'e.g. Damaged goods, breakage, counting correction',
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _busy || _units.isEmpty ? null : _saveCount,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save count'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _reviewCard() {
    final productById = {for (final product in _products) product.id: product};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Count review',
              style: TextStyle(
                color: AppTheme.navy,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            if (_lines.isEmpty)
              const Text(
                'No products counted yet.',
                style: TextStyle(color: AppTheme.textMuted),
              )
            else
              ..._lines.map((line) {
                final product = productById[line['product_id']];
                final system = (line['system_quantity_base'] as num).toDouble();
                final counted =
                    (line['counted_quantity_base'] as num).toDouble();
                final variance =
                    (line['variance_quantity_base'] as num).toDouble();
                final unit = product?.baseUnit ?? 'base units';
                final varianceText =
                    '${variance > 0 ? '+' : ''}${_quantity(variance)} $unit';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              product?.name ?? 'Product no longer available',
                              style: const TextStyle(
                                color: AppTheme.navy,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            variance.abs() <= 0.000001 ? 'Match' : varianceText,
                            style: TextStyle(
                              color: variance.abs() <= 0.000001
                                  ? Colors.green
                                  : variance > 0
                                      ? Colors.green
                                      : AppTheme.danger,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'System: ${_quantity(system)} $unit  Ã‚Â·  Counted: ${_quantity(counted)} $unit',
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      if ((line['reason'] as String?)?.trim().isNotEmpty ??
                          false)
                        Text(
                          'Reason: ${line['reason']}',
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
