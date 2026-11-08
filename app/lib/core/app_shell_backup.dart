import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'module_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int selected = 0;

  static const items = <_NavItem>[
    _NavItem('Dashboard', Icons.dashboard_outlined),
    _NavItem('Point of sale', Icons.point_of_sale_outlined),
    _NavItem('Products & stock', Icons.inventory_2_outlined),
    _NavItem('Customers & debts', Icons.people_alt_outlined),
    _NavItem('Suppliers', Icons.local_shipping_outlined),
    _NavItem('Expenses', Icons.receipt_long_outlined),
    _NavItem('Workers & payroll', Icons.badge_outlined),
    _NavItem('Reports', Icons.analytics_outlined),
    _NavItem('Notifications', Icons.notifications_none),
    _NavItem('Synchronization', Icons.sync),
    _NavItem('Audit trail', Icons.fact_check_outlined),
    _NavItem('Settings', Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final page = _buildPage(selected);
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            backgroundColor: Colors.white,
            extended: MediaQuery.sizeOf(context).width >= 1150,
            selectedIndex: selected,
            onDestinationSelected: (v) => setState(() => selected = v),
            leading: const Padding(
              padding: EdgeInsets.fromLTRB(16, 22, 16, 22),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.storefront, color: AppTheme.green, size: 30),
                SizedBox(width: 10),
                Text('SOKOPOA', style: TextStyle(
                  color: AppTheme.navy, fontWeight: FontWeight.w900, fontSize: 19)),
              ]),
            ),
            destinations: [
              for (final item in items)
                NavigationRailDestination(
                  icon: Icon(item.icon), label: Text(item.label)),
            ],
          ),
          const VerticalDivider(width: 1, color: Color(0xFFE7ECF2)),
          Expanded(child: page),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('SOKOPOA', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 18),
            child: Tooltip(message: 'Offline-first mode', child: Icon(
              Icons.cloud_off_outlined, color: AppTheme.amber)),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(child: ListView(children: [
          const ListTile(
            leading: Icon(Icons.storefront, color: AppTheme.green, size: 30),
            title: Text('SOKOPOA', style: TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text('Wholesale management'),
          ),
          const Divider(),
          for (var i = 0; i < items.length; i++)
            ListTile(
              leading: Icon(items[i].icon),
              title: Text(items[i].label),
              selected: selected == i,
              onTap: () {
                setState(() => selected = i);
                Navigator.pop(context);
              },
            ),
        ])),
      ),
      body: page,
    );
  }

  Widget _buildPage(int index) {
    if (index == 0) return const _DashboardPage();
    final item = items[index];
    return ModulePage(
      title: item.label,
      description: _descriptions[index],
      icon: item.icon,
      actions: _actions[index],
      columns: _columns[index],
    );
  }

  static const _descriptions = [
    '', 'Fast checkout and payment recording.',
    'Product catalogue, stock levels and stock movements.',
    'Customer profiles, credit sales and repayment tracking.',
    'Supplier records, purchases and balances.',
    'Operating expenses and supporting records.',
    'Staff access, activity tracking, wages and salary payments.',
    'Daily, weekly, monthly and custom business reports.',
    'Business alerts, approvals and notification history.',
    'Offline queue, sync status, retries and conflict review.',
    'Traceable records of important business activities.',
    'Business profile, devices, roles and application preferences.',
  ];

  static const _actions = [
    <String>[], ['New sale', 'Scan barcode'], ['Add product', 'Receive stock', 'Stocktake'],
    ['Add customer', 'Record payment'], ['Add supplier', 'Record purchase'],
    ['Record expense'], ['Add worker', 'Record payment'], ['Export report'],
    ['Review alerts'], ['Retry synchronization'], ['Export audit log'], ['Business profile'],
  ];

  static const _columns = [
    <String>[], ['Product search', 'Cart', 'Discount', 'Split payment', 'Receipt'],
    ['Code', 'Category', 'Buying cost', 'Selling price', 'Units', 'Quantity', 'Minimum stock'],
    ['Contact', 'Credit limit', 'Purchases', 'Paid', 'Balance'],
    ['Contact', 'Purchase history', 'Payments', 'Outstanding balance'],
    ['Category', 'Amount', 'Date', 'Method', 'Recorded by'],
    ['Role', 'Permissions', 'Activity', 'Salary', 'Advances', 'Deductions'],
    ['Sales', 'COGS', 'Gross profit', 'Expenses', 'Net operating profit'],
    ['Low stock', 'Out of stock', 'Approvals', 'Acknowledgements'],
    ['Connection', 'Pending records', 'Failed records', 'Last successful sync'],
    ['User', 'Device', 'Action', 'Previous value', 'New value', 'Timestamp'],
    ['Business', 'Users', 'Devices', 'Backups', 'Preferences'],
  ];
}

class _NavItem {
  const _NavItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _DashboardPage extends StatelessWidget {
  const _DashboardPage();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Business overview', style: TextStyle(
          fontSize: 25, fontWeight: FontWeight.w900, color: AppTheme.navy)),
        const SizedBox(height: 5),
        const Text('SOKOPOA wholesale management',
          style: TextStyle(color: AppTheme.textMuted)),
        const SizedBox(height: 20),
        Wrap(spacing: 12, runSpacing: 12, children: const [
          _Metric('Today sales', 'KES 0.00', Icons.trending_up, AppTheme.green),
          _Metric('Gross profit', 'KES 0.00', Icons.account_balance, AppTheme.navy),
          _Metric('Low stock', '0 items', Icons.warning_amber, AppTheme.amber),
          _Metric('Customer debts', 'KES 0.00', Icons.people, AppTheme.danger),
        ]),
        const SizedBox(height: 20),
        Card(child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text('Synchronization status', style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.navy)),
            SizedBox(height: 12),
            Row(children: [
              Icon(Icons.cloud_off_outlined, color: AppTheme.amber),
              SizedBox(width: 8),
              Expanded(child: Text('Offline-ready foundation — cloud sync is not configured yet')),
            ]),
            SizedBox(height: 8),
            Text('Pending records: 0  •  Last successful sync: Not yet synchronized',
              style: TextStyle(color: AppTheme.textMuted)),
          ]),
        )),
        const SizedBox(height: 16),
        const Card(child: Padding(
          padding: EdgeInsets.all(18),
          child: Text('Recent activity\n\nNo business transactions have been recorded yet.',
            style: TextStyle(height: 1.6)),
        )),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon, this.color);
  final String label, value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Card(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color),
        const SizedBox(height: 12),
        Text(value, style: const TextStyle(
          fontSize: 21, fontWeight: FontWeight.w900, color: AppTheme.navy)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: AppTheme.textMuted)),
      ]),
    )),
  );
}
