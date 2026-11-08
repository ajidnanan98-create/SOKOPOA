import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../reports/models/business_report.dart';
import '../repositories/dashboard_repository.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.loadDashboardData,
  });

  final Future<DashboardData> Function()? loadDashboardData;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  BusinessReport? _report;
  List<Map<String, Object?>> _recentSales = [];
  int _pendingCount = 0;
  int _failedCount = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data = await (widget.loadDashboardData?.call() ??
          DashboardRepository().getDashboardData());

      if (!mounted) return;

      setState(() {
        _report = data.report;
        _recentSales = data.recentSales;
        _pendingCount = data.pendingCount;
        _failedCount = data.failedCount;
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

  String _saleTime(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return 'Time unavailable';
    return parsed.toLocal().toString().substring(0, 16);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Business overview',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Live wholesale business performance',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh dashboard',
                onPressed: _loading ? null : _loadDashboard,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Dashboard data could not be loaded.'),
                    const SizedBox(height: 8),
                    Text(_error!, style: theme.textTheme.bodySmall),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _loadDashboard,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_report != null) ...[
            Text(
              'Today\'s performance',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _DashboardMetric(
                  'Today sales',
                  formatKes(_report!.sales.netSalesMinor),
                  Icons.trending_up,
                  AppTheme.green,
                ),
                _DashboardMetric(
                  'Collections',
                  formatKes(_report!.collections.totalMinor),
                  Icons.payments_outlined,
                  colors.primary,
                ),
                _DashboardMetric(
                  'Gross profit',
                  formatKes(_report!.profit.grossProfitMinor),
                  Icons.account_balance,
                  colors.primary,
                ),
                _DashboardMetric(
                  'Customer debts',
                  formatKes(_report!.debts.outstandingMinor),
                  Icons.people,
                  AppTheme.danger,
                ),
                _DashboardMetric(
                  'Low stock',
                  '${_report!.inventory.lowStockCount} items',
                  Icons.warning_amber,
                  AppTheme.amber,
                ),
                _DashboardMetric(
                  'Out of stock',
                  '${_report!.inventory.outOfStockCount} items',
                  Icons.inventory,
                  AppTheme.danger,
                ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Synchronization status',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.cloud_off_outlined, color: AppTheme.amber),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Offline-ready foundation â€” cloud sync is not configured yet',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pending records: $_pendingCount  â€¢  Failed records: $_failedCount',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recent sales',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_recentSales.isEmpty && !_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No sales have been recorded yet.'),
                    ),
                  for (final sale in _recentSales)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        child: Icon(Icons.receipt_long),
                      ),
                      title: Text(
                        sale['receipt_number']?.toString() ?? 'Sale',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${sale['customer_name'] ?? 'Walk-in customer'}\\n${_saleTime(sale['occurred_at'])}',
                      ),
                      isThreeLine: true,
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatKes(
                              (sale['total_minor'] as num?)?.toInt() ?? 0,
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Paid ${formatKes((sale['paid_minor'] as num?)?.toInt() ?? 0)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardMetric extends StatelessWidget {
  const _DashboardMetric(
    this.label,
    this.value,
    this.icon,
    this.color,
  );

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 220,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color),
                const SizedBox(height: 12),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(height: 4),
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      );
}
