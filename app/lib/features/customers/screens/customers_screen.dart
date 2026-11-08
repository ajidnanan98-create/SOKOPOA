import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/app_theme.dart';
import '../models/customer.dart';
import '../repositories/customer_repository.dart';

import '../models/customer_repayment_history_entry.dart';
import '../../pos/models/sale_payment.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({
    super.key,
    required this.actorUserId,
    required this.deviceId,
    CustomerRepository? repository,
  }) : _repository = repository;

  final String actorUserId;
  final String deviceId;
  final CustomerRepository? _repository;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  late final CustomerRepository _repository;
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _moneyFormat = NumberFormat('#,##0.00');

  List<Customer> _customers = [];
  final Map<String, int> _debts = {};

  bool _isLoading = true;
  String? _errorMessage;
  String _search = '';

  String _money(int minorUnits) {
    return 'KSh ${_moneyFormat.format(minorUnits / 100)}';
  }

  @override
  void initState() {
    super.initState();
    _repository = widget._repository ?? CustomerRepository();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final customers = await _repository.getCustomers(
        search: _search,
      );

      final debts = <String, int>{};

      for (final customer in customers) {
        debts[customer.id] =
            await _repository.getOutstandingDebtMinor(customer.id);
      }

      if (!mounted) return;

      setState(() {
        _customers = customers;
        _debts
          ..clear()
          ..addAll(debts);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final totalDebt = _debts.values.fold<int>(
      0,
      (total, amount) => total + amount,
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadCustomers,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 800;

              return ListView(
                padding: EdgeInsets.all(wide ? 24 : 16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Customers & Debts',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppTheme.navy,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Manage customer accounts and repayments',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh customers',
                        onPressed: _loadCustomers,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: () => _showCustomerForm(),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Register customer'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TOTAL OUTSTANDING DEBT',
                            style: theme.textTheme.labelMedium?.copyWith(
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _money(totalDebt),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: AppTheme.amber,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_customers.length} customers found',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      _search = value;
                      _loadCustomers();
                    },
                    decoration: InputDecoration(
                      hintText: 'Search name, phone or email',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _searchController.clear();
                                _search = '';
                                _loadCustomers();
                              },
                              icon: const Icon(Icons.close),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_errorMessage != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          'Could not load customers: $_errorMessage',
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                    )
                  else if (_customers.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Center(
                          child: Text('No customers found.'),
                        ),
                      ),
                    )
                  else
                    ..._customers.map((customer) {
                      final debt = _debts[customer.id] ?? 0;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: colors.primaryContainer,
                            child: Text(
                              customer.name.isEmpty
                                  ? '?'
                                  : customer.name[0].toUpperCase(),
                            ),
                          ),
                          title: Text(
                            customer.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            customer.phone ?? customer.email ?? 'No contact',
                          ),
                          onTap: () => _showCustomerDetails(customer),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _money(debt),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: debt > 0
                                      ? AppTheme.amber
                                      : AppTheme.green,
                                ),
                              ),
                              Text(
                                debt > 0 ? 'Outstanding' : 'Clear',
                                style: theme.textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showCustomerDetails(Customer customer) async {
    final debt = await _repository.getOutstandingDebtMinor(customer.id);

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);

        return AlertDialog(
          title: Text(customer.name),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CUSTOMER ACCOUNT'),
                  const SizedBox(height: 12),
                  _customerDetailRow(
                    'Phone',
                    customer.phone?.isNotEmpty == true
                        ? customer.phone!
                        : 'Not provided',
                  ),
                  _customerDetailRow(
                    'Email',
                    customer.email?.isNotEmpty == true
                        ? customer.email!
                        : 'Not provided',
                  ),
                  _customerDetailRow(
                    'Credit limit',
                    _money(customer.creditLimitMinor),
                  ),
                  const Divider(height: 24),
                  Text(
                    'Outstanding debt',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _money(debt),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: debt > 0 ? AppTheme.amber : AppTheme.green,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    debt > 0
                        ? 'This customer has an unpaid balance.'
                        : 'This customer has no outstanding debt.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _showRepaymentHistory(customer);
              },
              icon: const Icon(Icons.history),
              label: const Text('History'),
            ),
            if (debt > 0)
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _showRepaymentForm(customer);
                },
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Record repayment'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _showCustomerForm(customer: customer);
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit customer'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showRepaymentForm(Customer customer) async {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController();
    final referenceController = TextEditingController();
    final receivedByController = TextEditingController(
      text: widget.actorUserId,
    );

    String selectedMethod = 'cash';

    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Record repayment — ${customer.name}'),
            content: SizedBox(
              width: 440,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Amount received (KES) *',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                        validator: (value) {
                          final amount = double.tryParse(
                            (value ?? '').trim(),
                          );
                          if (amount == null ||
                              !amount.isFinite ||
                              amount <= 0 ||
                              amount > 90000000000000) {
                            return 'Enter a valid amount greater than zero.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedMethod,
                        decoration: const InputDecoration(
                          labelText: 'Payment method',
                          prefixIcon: Icon(Icons.account_balance_wallet),
                        ),
                        items: SalePayment.supportedMethods.map((method) {
                          return DropdownMenuItem(
                            value: method,
                            child: Text(method.toUpperCase()),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() {
                              selectedMethod = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: referenceController,
                        decoration: const InputDecoration(
                          labelText: 'Transaction reference (optional)',
                          prefixIcon: Icon(Icons.receipt_long_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: receivedByController,
                        decoration: const InputDecoration(
                          labelText: 'Received by *',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Enter who received the payment.'
                                : null,
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
              FilledButton.icon(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(dialogContext, true);
                  }
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Record payment'),
              ),
            ],
          ),
        ),
      );

      if (result != true || !mounted) return;

      final amountMinor =
          (double.parse(amountController.text.trim()) * 100).round();

      final repayment = await _repository.recordRepayment(
        customerId: customer.id,
        payment: SalePayment(
          method: selectedMethod,
          amountMinor: amountMinor,
          reference: referenceController.text.trim(),
        ),
        receivedBy: receivedByController.text.trim(),
        actorUserId: widget.actorUserId,
        deviceId: widget.deviceId,
      );

      if (!mounted) return;

      await _loadCustomers();

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Repayment recorded'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Received: ${_money(repayment.amountMinor)}'),
                  Text('Method: ${repayment.method.toUpperCase()}'),
                  if (repayment.reference?.isNotEmpty == true)
                    Text('Reference: ${repayment.reference}'),
                  const Divider(height: 24),
                  const Text(
                    'Payment allocations',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ...repayment.allocations.map(
                    (allocation) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Receipt: ${allocation.receiptNumber}'),
                          Text('Allocated: ${_money(allocation.amountMinor)}'),
                          Text('Remaining: ${_money(allocation.balanceMinor)}'),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 24),
                  Text(
                    'Remaining customer debt: '
                    '${_money(repayment.remainingDebtMinor)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not record repayment: $error')),
      );
    } finally {
      amountController.dispose();
      referenceController.dispose();
      receivedByController.dispose();
    }
  }

  Future<void> _showRepaymentHistory(Customer customer) async {
    try {
      final List<CustomerRepaymentHistoryEntry> entries =
          await _repository.getRepaymentHistory(customer.id);

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Repayment history — ${customer.name}'),
          content: SizedBox(
            width: 560,
            child: entries.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No repayments have been recorded yet.'),
                  )
                : SizedBox(
                    height: 420,
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: entries.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 20),
                      itemBuilder: (context, index) {
                        final entry = entries[index];

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _money(entry.amountMinor),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                Text(
                                  entry.method.toUpperCase(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text('Receipt: ${entry.receiptNumber}'),
                            if (entry.reference?.isNotEmpty == true)
                              Text('Reference: ${entry.reference}'),
                            Text('Received by: ${entry.receivedBy}'),
                            Text(
                              DateFormat('dd MMM yyyy, hh:mm a')
                                  .format(entry.occurredAt.toLocal()),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load repayment history: $error')),
      );
    }
  }

  Widget _customerDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<void> _showCustomerForm({Customer? customer}) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: customer?.name ?? '');
    final phoneController = TextEditingController(text: customer?.phone ?? '');
    final emailController = TextEditingController(text: customer?.email ?? '');
    final creditController = TextEditingController(
      text: customer == null
          ? ''
          : (customer.creditLimitMinor / 100).toStringAsFixed(2),
    );

    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(customer == null ? 'Register customer' : 'Edit customer'),
          content: SizedBox(
            width: 440,
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
                        labelText: 'Customer name *',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Customer name is required.'
                              : null,
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
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (email.isNotEmpty &&
                            !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                .hasMatch(email)) {
                          return 'Enter a valid email address.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: creditController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Credit limit (KES)',
                        prefixIcon: Icon(
                          Icons.account_balance_wallet_outlined,
                        ),
                        helperText: 'Enter 0 for no credit allowance.',
                      ),
                      validator: (value) {
                        final amount = double.tryParse(
                          (value ?? '').trim().isEmpty ? '0' : value!.trim(),
                        );
                        if (amount == null ||
                            !amount.isFinite ||
                            amount < 0 ||
                            amount > 90000000000000) {
                          return 'Enter a valid non-negative amount.';
                        }
                        return null;
                      },
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
            FilledButton.icon(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              icon: const Icon(Icons.save_outlined),
              label: Text(customer == null ? 'Register' : 'Save changes'),
            ),
          ],
        ),
      );

      if (result != true || !mounted) return;

      final creditAmount = double.tryParse(
            creditController.text.trim().isEmpty
                ? '0'
                : creditController.text.trim(),
          ) ??
          0;
      final creditLimitMinor = (creditAmount * 100).round();

      if (customer == null) {
        await _repository.createCustomer(
          name: nameController.text,
          phone: phoneController.text,
          email: emailController.text,
          creditLimitMinor: creditLimitMinor,
          actorUserId: widget.actorUserId,
          deviceId: widget.deviceId,
        );
      } else {
        await _repository.updateCustomer(
          customerId: customer.id,
          name: nameController.text,
          phone: phoneController.text,
          email: emailController.text,
          creditLimitMinor: creditLimitMinor,
          actorUserId: widget.actorUserId,
          deviceId: widget.deviceId,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            customer == null
                ? 'Customer registered successfully.'
                : 'Customer updated successfully.',
          ),
        ),
      );
      await _loadCustomers();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save customer: $error')),
      );
    } finally {
      nameController.dispose();
      phoneController.dispose();
      emailController.dispose();
      creditController.dispose();
    }
  }
}
