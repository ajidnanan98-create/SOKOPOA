import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/app_theme.dart';
import '../models/business_report.dart';
import '../repositories/business_report_repository.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    BusinessReportRepository? repository,
  }) : _repository = repository;

  final BusinessReportRepository? _repository;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final BusinessReportRepository _repository;

  BusinessReport? _report;

  bool _isLoading = true;
  String? _errorMessage;

  late DateTime _from;
  late DateTime _to;

  final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();

    _repository = widget._repository ?? BusinessReportRepository();

    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day);

    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _repository.getBusinessReport(
        from: _from,
        to: _to,
      );

      if (!mounted) return;

      setState(() {
        _report = result;
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

  Future<void> _selectDateRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: _from,
        end: _to,
      ),
      helpText: 'Select report period',
    );

    if (selected == null || !mounted) return;

    setState(() {
      _from = selected.start;
      _to = selected.end;
    });

    await _loadReport();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 800;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadReport,
          child: ListView(
            padding: EdgeInsets.all(wide ? 24 : 16),
            children: [
              _buildHeader(theme, colors),
              const SizedBox(height: 16),
              _buildDateFilter(theme),
              const SizedBox(height: 20),
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_errorMessage != null)
                _buildErrorState(theme)
              else if (_report != null)
                _buildReportContent(_report!, wide),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme colors) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Business reports',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.brightness == Brightness.dark
                      ? colors.onSurface
                      : AppTheme.navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Monitor sales, finances, stock and performance',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh reports',
          onPressed: _isLoading ? null : _loadReport,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  Widget _buildDateFilter(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.calendar_month_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'REPORTING PERIOD',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_dateFormat.format(_from)} - '
                    '${_dateFormat.format(_to)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _selectDateRange,
              icon: const Icon(Icons.edit_calendar_outlined, size: 18),
              label: const Text('Change'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 42,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Could not load reports',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'An unexpected error occurred.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadReport,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewSection(
    BusinessReport data,
    ThemeData theme,
  ) {
    final cards = [
      _buildMetricCard(
        title: 'Net sales',
        value: formatKes(data.sales.netSalesMinor),
        icon: Icons.point_of_sale,
        color: AppTheme.navy,
        theme: theme,
      ),
      _buildMetricCard(
        title: 'Collections',
        value: formatKes(data.collections.totalMinor),
        icon: Icons.payments_outlined,
        color: AppTheme.green,
        theme: theme,
      ),
      _buildMetricCard(
        title: 'Gross profit',
        value: formatKes(data.profit.grossProfitMinor),
        icon: Icons.trending_up,
        color: AppTheme.green,
        theme: theme,
      ),
      _buildMetricCard(
        title: 'Expenses',
        value: formatKes(data.expenses.totalMinor),
        icon: Icons.receipt_long_outlined,
        color: AppTheme.amber,
        theme: theme,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 4
            : constraints.maxWidth >= 560
                ? 2
                : 1;

        const spacing = 12.0;
        final cardWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map(
                (card) => SizedBox(
                  width: cardWidth,
                  child: card,
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required ThemeData theme,
  }) {
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colors.outline.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 21,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.analytics_outlined,
                color: colors.onSurface.withValues(alpha: 0.35),
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportContent(BusinessReport data, bool wide) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeading('Financial overview', theme),
        _buildOverviewSection(data, theme),
        const SizedBox(height: 24),
        _buildSectionHeading('Customer debts', theme),
        _buildMetricGrid([
          _buildMetricCard(
            title: 'Outstanding customer debt',
            value: formatKes(data.debts.outstandingMinor),
            icon: Icons.account_balance_wallet_outlined,
            color: AppTheme.amber,
            theme: theme,
          ),
          _buildMetricCard(
            title: 'Customers with outstanding debt',
            value: '${data.debts.customerCount}',
            icon: Icons.people_outline,
            color: AppTheme.navy,
            theme: theme,
          ),
        ]),
        const SizedBox(height: 24),
        _buildSectionHeading('Inventory position', theme),
        _buildMetricGrid([
          _buildMetricCard(
            title: 'Active products',
            value: '${data.inventory.productCount}',
            icon: Icons.inventory_2_outlined,
            color: AppTheme.navy,
            theme: theme,
          ),
          _buildMetricCard(
            title: 'Current stock value',
            value: formatKes(data.inventory.stockValueMinor),
            icon: Icons.warehouse_outlined,
            color: AppTheme.green,
            theme: theme,
          ),
          _buildMetricCard(
            title: 'Potential sales value',
            value: formatKes(data.inventory.potentialSalesMinor),
            icon: Icons.sell_outlined,
            color: AppTheme.green,
            theme: theme,
          ),
          _buildMetricCard(
            title: 'Low-stock products',
            value: '${data.inventory.lowStockCount}',
            icon: Icons.warning_amber_outlined,
            color: AppTheme.amber,
            theme: theme,
          ),
          _buildMetricCard(
            title: 'Out-of-stock products',
            value: '${data.inventory.outOfStockCount}',
            icon: Icons.remove_shopping_cart_outlined,
            color: AppTheme.danger,
            theme: theme,
          ),
        ]),
        const SizedBox(height: 24),
        _buildSectionHeading('Workers', theme),
        _buildMetricGrid([
          _buildMetricCard(
            title: 'Active workers',
            value: '${data.workers.workerCount}',
            icon: Icons.badge_outlined,
            color: AppTheme.navy,
            theme: theme,
          ),
          _buildMetricCard(
            title: 'Unassigned sales',
            value: '${data.workers.unassignedSalesCount}',
            icon: Icons.person_off_outlined,
            color: AppTheme.amber,
            theme: theme,
          ),
        ]),
        const SizedBox(height: 12),
        _buildWorkerPerformance(data, theme),
        const SizedBox(height: 24),
        _buildSectionHeading('Suppliers', theme),
        _buildMetricGrid([
          _buildMetricCard(
            title: 'Suppliers with invoices',
            value: '${data.suppliers.supplierCount}',
            icon: Icons.local_shipping_outlined,
            color: AppTheme.navy,
            theme: theme,
          ),
          _buildMetricCard(
            title: 'Supplier invoices',
            value: '${data.suppliers.invoiceCount}',
            icon: Icons.receipt_long_outlined,
            color: AppTheme.navy,
            theme: theme,
          ),
          _buildMetricCard(
            title: 'Invoice total',
            value: formatKes(data.suppliers.invoiceTotalMinor),
            icon: Icons.description_outlined,
            color: AppTheme.green,
            theme: theme,
          ),
          _buildMetricCard(
            title: 'Payments made in period',
            value: formatKes(data.suppliers.amountPaidMinor),
            icon: Icons.payments_outlined,
            color: AppTheme.green,
            theme: theme,
          ),
          _buildMetricCard(
            title: 'Current outstanding supplier balance',
            value: formatKes(data.suppliers.outstandingMinor),
            icon: Icons.account_balance_outlined,
            color: AppTheme.amber,
            theme: theme,
          ),
        ]),
      ],
    );
  }

  Widget _buildWorkerPerformance(
    BusinessReport data,
    ThemeData theme,
  ) {
    final workers = data.workers.salesByWorker;
    final colors = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sales by worker',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            if (workers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No worker-attributed sales in this period.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              )
            else
              ...workers.map(
                (worker) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        child: Text(
                          worker.workerName.isEmpty
                              ? '?'
                              : worker.workerName[0].toUpperCase(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              worker.workerName,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${worker.transactionCount} transactions',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatKes(worker.salesMinor),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeading(String heading, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        heading,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.brightness == Brightness.dark
              ? theme.colorScheme.onSurface
              : AppTheme.navy,
        ),
      ),
    );
  }

  Widget _buildMetricGrid(List<Widget> cards) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 4
            : constraints.maxWidth >= 560
                ? 2
                : 1;

        const spacing = 12.0;
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map(
                (card) => SizedBox(
                  width: cardWidth,
                  child: card,
                ),
              )
              .toList(),
        );
      },
    );
  }
}
