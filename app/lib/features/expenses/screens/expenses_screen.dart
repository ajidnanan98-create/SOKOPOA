import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/app_theme.dart';
import '../models/expense.dart';
import '../repositories/expense_repository.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({
    super.key,
    required this.actorUserId,
    required this.deviceId,
    ExpenseRepository? repository,
  }) : _repository = repository;

  final String actorUserId;
  final String deviceId;
  final ExpenseRepository? _repository;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  late final ExpenseRepository _repository;

  final _searchController = TextEditingController();
  final _moneyFormat = NumberFormat('#,##0.00');
  final _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

  List<Expense> _expenses = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _search = '';
  String _category = '';
  DateTime? _from;
  DateTime? _to;

  static const _categories = [
    'Rent',
    'Transport',
    'Fuel',
    'Electricity',
    'Water',
    'Salaries',
    'Repairs',
    'Packaging',
    'Communication',
    'Licences',
    'Other',
  ];

  String _money(int minorUnits) =>
      'KSh ${_moneyFormat.format(minorUnits / 100)}';

  @override
  void initState() {
    super.initState();
    _repository = widget._repository ?? ExpenseRepository();
    _loadExpenses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadExpenses() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final expenses = await _repository.getExpenses(
        search: _search,
        category: _category.isEmpty ? null : _category,
        from: _from,
        to: _to,
      );

      if (!mounted) return;

      setState(() {
        _expenses = expenses;
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
    final today = DateUtils.dateOnly(DateTime.now());

    final total = _expenses.fold<int>(
      0,
      (sum, expense) => sum + expense.amountMinor,
    );

    final todayTotal = _expenses
        .where((expense) =>
            DateUtils.isSameDay(expense.occurredAt.toLocal(), today))
        .fold<int>(0, (sum, expense) => sum + expense.amountMinor);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadExpenses,
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
                              'Expenses',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: theme.brightness == Brightness.dark
                                    ? colors.onSurface
                                    : AppTheme.navy,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Track and manage wholesale business expenses',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh expenses',
                        onPressed: _loadExpenses,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: () => _showExpenseForm(),
                      icon: const Icon(Icons.add),
                      label: const Text('Record expense'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: wide ? 3 : 1,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: wide ? 2.5 : 3.5,
                    children: [
                      _summaryCard(
                        title: 'TOTAL EXPENSES',
                        amount: _money(total),
                        subtitle: '${_expenses.length} records',
                        icon: Icons.account_balance_wallet_outlined,
                        color: colors.primary,
                      ),
                      _summaryCard(
                        title: "TODAY'S EXPENSES",
                        amount: _money(todayTotal),
                        subtitle: 'Recorded today',
                        icon: Icons.today_outlined,
                        color: AppTheme.amber,
                      ),
                      _summaryCard(
                        title: 'AVERAGE EXPENSE',
                        amount: _money(
                          _expenses.isEmpty ? 0 : total ~/ _expenses.length,
                        ),
                        subtitle: 'Per recorded expense',
                        icon: Icons.analytics_outlined,
                        color: AppTheme.green,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      _search = value;
                      _loadExpenses();
                    },
                    decoration: InputDecoration(
                      hintText: 'Search category or description',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _searchController.clear();
                                _search = '';
                                _loadExpenses();
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: wide ? 220 : constraints.maxWidth - 32,
                        child: DropdownButtonFormField<String>(
                          initialValue: _category,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            prefixIcon: Icon(Icons.category_outlined),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('All categories'),
                            ),
                            ..._categories.map(
                              (category) => DropdownMenuItem(
                                value: category,
                                child: Text(category),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => _category = value ?? '');
                            _loadExpenses();
                          },
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _selectDateRange,
                        icon: const Icon(Icons.date_range),
                        label: Text(
                          _from == null
                              ? 'Filter dates'
                              : '${DateFormat('dd MMM').format(_from!)} – '
                                  '${DateFormat('dd MMM').format(_to!)}',
                        ),
                      ),
                      if (_from != null)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _from = null;
                              _to = null;
                            });
                            _loadExpenses();
                          },
                          child: const Text('Clear dates'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Expense history',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '${_expenses.length} records',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_errorMessage != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          'Could not load expenses: $_errorMessage',
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                    )
                  else if (_expenses.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.receipt_long_outlined,
                                size: 42,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'No expenses found',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Record an expense or change your filters.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    ..._expenses.map(_expenseCard),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _summaryCard({
    required String title,
    required String amount,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 23,
              backgroundColor: color.withValues(alpha: 0.14),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 5),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      amount,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
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

  Widget _expenseCard(Expense expense) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        leading: CircleAvatar(
          backgroundColor: colors.primaryContainer,
          child: Icon(
            Icons.receipt_long_outlined,
            color: colors.onPrimaryContainer,
          ),
        ),
        title: Text(
          expense.category,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (expense.description?.isNotEmpty == true)
              Text(expense.description!),
            const SizedBox(height: 4),
            Text(
              '${expense.paymentMethod.toUpperCase()} • '
              '${_dateFormat.format(expense.occurredAt.toLocal())}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Expense actions',
          onSelected: (value) {
            if (value == 'edit') {
              _showExpenseForm(expense: expense);
            } else if (value == 'delete') {
              _confirmDelete(expense);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'edit',
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Edit'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Delete'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _money(expense.amountMinor),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'View actions',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectDateRange() async {
    final now = DateTime.now();

    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1),
      initialDateRange:
          _from == null ? null : DateTimeRange(start: _from!, end: _to!),
    );

    if (range == null || !mounted) return;

    setState(() {
      _from = DateTime(
        range.start.year,
        range.start.month,
        range.start.day,
      );
      _to = DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
        23,
        59,
        59,
        999,
      );
    });

    await _loadExpenses();
  }

  Future<void> _showExpenseForm({Expense? expense}) async {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController(
      text:
          expense == null ? '' : (expense.amountMinor / 100).toStringAsFixed(2),
    );
    final descriptionController = TextEditingController(
      text: expense?.description ?? '',
    );

    String selectedCategory = expense?.category ?? _categories.first;
    String selectedMethod = expense?.paymentMethod ?? 'cash';
    DateTime selectedDate = expense?.occurredAt.toLocal() ?? DateTime.now();

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final theme = Theme.of(context);

            return AlertDialog(
              title: Text(
                expense == null ? 'Record expense' : 'Edit expense',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: SizedBox(
                width: 460,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: selectedCategory,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Expense category',
                            prefixIcon: Icon(Icons.category_outlined),
                          ),
                          items: _categories
                              .map(
                                (category) => DropdownMenuItem(
                                  value: category,
                                  child: Text(category),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(
                                () => selectedCategory = value,
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: amountController,
                          autofocus: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Amount (KES) *',
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
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: selectedMethod,
                          decoration: const InputDecoration(
                            labelText: 'Payment method',
                            prefixIcon: Icon(Icons.account_balance_wallet),
                          ),
                          items: ExpenseRepository.supportedPaymentMethods
                              .map(
                                (method) => DropdownMenuItem(
                                  value: method,
                                  child: Text(method.toUpperCase()),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(
                                () => selectedMethod = value,
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: descriptionController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Description (optional)',
                            prefixIcon: Icon(Icons.notes_outlined),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.calendar_today_outlined),
                          title: const Text('Expense date'),
                          subtitle: Text(
                            DateFormat('dd MMM yyyy').format(selectedDate),
                          ),
                          trailing: const Icon(Icons.edit_calendar_outlined),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: dialogContext,
                              initialDate: selectedDate,
                              firstDate: DateTime(
                                DateTime.now().year - 10,
                              ),
                              lastDate: DateTime(
                                DateTime.now().year + 1,
                              ),
                            );

                            if (picked != null) {
                              setDialogState(() {
                                selectedDate = DateTime(
                                  picked.year,
                                  picked.month,
                                  picked.day,
                                  selectedDate.hour,
                                  selectedDate.minute,
                                );
                              });
                            }
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
                  label:
                      Text(expense == null ? 'Save expense' : 'Save changes'),
                ),
              ],
            );
          },
        ),
      );

      if (saved != true || !mounted) return;

      final amountMinor =
          (double.parse(amountController.text.trim()) * 100).round();

      if (expense == null) {
        await _repository.createExpense(
          category: selectedCategory,
          amountMinor: amountMinor,
          paymentMethod: selectedMethod,
          description: descriptionController.text,
          actorUserId: widget.actorUserId,
          deviceId: widget.deviceId,
          occurredAt: selectedDate,
        );
      } else {
        await _repository.updateExpense(
          expenseId: expense.id,
          category: selectedCategory,
          amountMinor: amountMinor,
          paymentMethod: selectedMethod,
          description: descriptionController.text,
          actorUserId: widget.actorUserId,
          deviceId: widget.deviceId,
          occurredAt: selectedDate,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            expense == null
                ? 'Expense recorded successfully.'
                : 'Expense updated successfully.',
          ),
        ),
      );

      await _loadExpenses();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save expense: $error')),
      );
    } finally {
      amountController.dispose();
      descriptionController.dispose();
    }
  }

  Future<void> _confirmDelete(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text(
          'Delete ${expense.category} expense of '
          '${_money(expense.amountMinor)}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _repository.deleteExpense(
        expenseId: expense.id,
        actorUserId: widget.actorUserId,
        deviceId: widget.deviceId,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense deleted successfully.')),
      );

      await _loadExpenses();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete expense: $error')),
      );
    }
  }
}
