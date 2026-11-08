import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/app_theme.dart';
import '../../purchasing/models/supplier.dart';
import '../../purchasing/models/supplier_invoice.dart';
import '../../purchasing/repositories/supplier_repository.dart';
import '../../purchasing/repositories/supplier_invoice_repository.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({
    super.key,
    required this.actorUserId,
    required this.deviceId,
    this.supplierRepository,
    this.invoiceRepository,
  });

  final String actorUserId;
  final String deviceId;
  final SupplierRepository? supplierRepository;
  final SupplierInvoiceRepository? invoiceRepository;

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  late final SupplierRepository _supplierRepository;
  late final SupplierInvoiceRepository _invoiceRepository;

  final TextEditingController _searchController = TextEditingController();

  List<Supplier> _suppliers = [];
  bool _loading = true;
  String? _error;
  String _search = '';

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get _surface => _isDark ? AppTheme.darkSurface : Colors.white;

  Color get _muted => _isDark ? AppTheme.darkMuted : AppTheme.textMuted;

  Color get _border => _isDark ? AppTheme.darkBorder : const Color(0xFFE7ECF2);

  @override
  void initState() {
    super.initState();
    _supplierRepository = widget.supplierRepository ?? SupplierRepository();
    _invoiceRepository =
        widget.invoiceRepository ?? SupplierInvoiceRepository();
    _loadSuppliers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final suppliers = await _supplierRepository.getSuppliers(
        search: _search,
      );

      if (!mounted) return;

      setState(() {
        _suppliers = suppliers;
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

  Future<void> _showSupplierForm({Supplier? supplier}) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: supplier?.name ?? '');
    final phoneController = TextEditingController(text: supplier?.phone ?? '');
    final emailController = TextEditingController(text: supplier?.email ?? '');
    final addressController =
        TextEditingController(text: supplier?.address ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            supplier == null ? 'Add supplier' : 'Edit supplier',
          ),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Supplier name *',
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Supplier name is required.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: addressController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: Text(supplier == null ? 'Save supplier' : 'Save changes'),
            ),
          ],
        );
      },
    );

    if (result != true || !mounted) {
      nameController.dispose();
      phoneController.dispose();
      emailController.dispose();
      addressController.dispose();
      return;
    }

    try {
      if (supplier == null) {
        await _supplierRepository.createSupplier(
          name: nameController.text,
          phone: phoneController.text,
          email: emailController.text,
          address: addressController.text,
          actorUserId: widget.actorUserId,
          deviceId: widget.deviceId,
        );
      } else {
        await _supplierRepository.updateSupplier(
          supplierId: supplier.id,
          name: nameController.text,
          phone: phoneController.text,
          email: emailController.text,
          address: addressController.text,
          actorUserId: widget.actorUserId,
          deviceId: widget.deviceId,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            supplier == null
                ? 'Supplier added successfully.'
                : 'Supplier updated successfully.',
          ),
        ),
      );

      await _loadSuppliers();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save supplier: $error')),
      );
    } finally {
      nameController.dispose();
      phoneController.dispose();
      emailController.dispose();
      addressController.dispose();
    }
  }

  Future<void> _showSupplierDetails(Supplier supplier) async {
    try {
      final invoices = await _invoiceRepository.getInvoices(
        supplierId: supplier.id,
      );

      if (!mounted) return;

      final balances = <String, int>{};

      for (final invoice in invoices) {
        balances[invoice.id] =
            await _invoiceRepository.getOutstandingBalanceMinor(
          invoice.id,
        );
      }

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final outstanding = invoices.fold<int>(
            0,
            (total, invoice) => total + (balances[invoice.id] ?? 0),
          );

          return AlertDialog(
            title: Text(supplier.name),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _detailRow('Phone', supplier.phone ?? 'Not provided'),
                    _detailRow('Email', supplier.email ?? 'Not provided'),
                    _detailRow(
                      'Address',
                      supplier.address ?? 'Not provided',
                    ),
                    const Divider(height: 24),
                    Text(
                      'Outstanding balance',
                      style: TextStyle(color: _muted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _money(outstanding),
                      style: TextStyle(
                        color:
                            outstanding > 0 ? AppTheme.amber : AppTheme.green,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(height: 24),
                    const Text(
                      'Supplier invoices',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (invoices.isEmpty)
                      Text(
                        'No invoices recorded for this supplier.',
                        style: TextStyle(color: _muted),
                      )
                    else
                      ...invoices.map(
                        (invoice) => _invoiceTile(
                          invoice,
                          balances[invoice.id] ?? 0,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _showSupplierForm(supplier: supplier);
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit supplier'),
              ),
            ],
          );
        },
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load supplier details: $error'),
        ),
      );
    }
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: TextStyle(color: _muted)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _invoiceTile(SupplierInvoice invoice, int balance) {
    final statusColor = switch (invoice.status) {
      'paid' => AppTheme.green,
      'part_paid' => AppTheme.amber,
      'void' => AppTheme.danger,
      _ => _muted,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  invoice.invoiceNumber,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                invoice.status.replaceAll('_', ' ').toUpperCase(),
                style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Invoice date: ${_date(invoice.invoiceDate)}'),
          if (invoice.dueDate != null)
            Text('Due date: ${_date(invoice.dueDate!)}'),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total: ${_money(invoice.totalMinor)}'),
              Text(
                'Balance: ${_money(balance)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: balance > 0 ? AppTheme.amber : AppTheme.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _money(int minor) {
    return NumberFormat.currency(
      locale: 'en_KE',
      symbol: 'KES ',
      decimalDigits: 2,
    ).format(minor / 100);
  }

  String _date(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;

    return DateFormat('dd MMM yyyy').format(parsed.toLocal());
  }

  Widget _buildSupplierCard(Supplier supplier) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showSupplierDetails(supplier),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.navy.withValues(alpha: 0.1),
                foregroundColor: _isDark ? AppTheme.darkText : AppTheme.navy,
                child: const Icon(Icons.business_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supplier.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (supplier.phone != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        supplier.phone!,
                        style: TextStyle(color: _muted, fontSize: 13),
                      ),
                    ],
                    if (supplier.email != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        supplier.email!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit supplier',
                onPressed: () => _showSupplierForm(supplier: supplier),
                icon: const Icon(Icons.edit_outlined),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadSuppliers,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_suppliers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.business_outlined, size: 54, color: _muted),
              const SizedBox(height: 12),
              const Text(
                'No suppliers found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _search.isEmpty
                    ? 'Add your first supplier to get started.'
                    : 'Try another search term.',
                style: TextStyle(color: _muted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1100
            ? 3
            : width >= 650
                ? 2
                : 1;

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 112,
          ),
          itemCount: _suppliers.length,
          itemBuilder: (context, index) =>
              _buildSupplierCard(_suppliers[index]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suppliers'),
        actions: [
          IconButton(
            tooltip: 'Refresh suppliers',
            onPressed: _loadSuppliers,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      _search = value;
                      _loadSuppliers();
                    },
                    decoration: InputDecoration(
                      hintText: 'Search suppliers...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _searchController.clear();
                                _search = '';
                                _loadSuppliers();
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => _showSupplierForm(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}
