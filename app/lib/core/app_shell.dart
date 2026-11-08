import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'owner_access_dialog.dart';
import 'owner_auth_service.dart';
import 'owner_session_manager.dart';
import 'app_theme.dart';
import 'app_theme_controller.dart';
import 'module_page.dart';
import 'sync_service.dart';
import 'backup_service.dart';
import '../features/pos/screens/pos_screen.dart';
import '../features/inventory/inventory_screen.dart';
import '../features/customers/screens/customers_screen.dart';
import '../features/suppliers/screens/suppliers_screen.dart';
import '../features/expenses/screens/expenses_screen.dart';
import '../features/workers/screens/workers_screen.dart';
import '../features/reports/screens/reports_screen.dart';
import '../features/dashboard/screens/dashboard_screen.dart';
import '../features/sync/screens/sync_screen.dart';
import '../features/notifications/screens/notifications_screen.dart';
import '../features/audit/screens/audit_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.themeController,
  });

  final AppThemeController themeController;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int selected = 1;

  late final OwnerSessionManager _ownerSessionManager;

  @override
  void initState() {
    super.initState();
    _ownerSessionManager = OwnerSessionManager(
      inactivityLimit: const Duration(minutes: 10),
      onTimeout: _lockOwnerSession,
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _ownerSessionManager.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _lockOwnerSession();
    }
  }

  void _lockOwnerSession() {
    _ownerSessionManager.cancel();
    OwnerAuthService.instance.lock();

    if (!mounted) return;

    if (selected == 0 || selected == 7) {
      setState(() => selected = 1);
    }
  }

  void _resetOwnerInactivityTimer() {
    if ((selected == 0 || selected == 7) &&
        OwnerAuthService.instance.isAuthenticated) {
      if (_ownerSessionManager.isActive) {
        _ownerSessionManager.recordActivity();
      } else {
        _ownerSessionManager.start();
      }
    } else {
      _ownerSessionManager.cancel();
    }
  }

  void _handleUserActivity() {
    _resetOwnerInactivityTimer();
  }

  Widget _withActivityDetection(Widget child) {
    return Listener(
      onPointerDown: (_) => _handleUserActivity(),
      onPointerMove: (_) => _handleUserActivity(),
      onPointerHover: (_) => _handleUserActivity(),
      child: Focus(
        onKeyEvent: (node, event) {
          _handleUserActivity();
          return KeyEventResult.ignored;
        },
        child: child,
      ),
    );
  }

  // Temporary local identifiers for this foundation milestone.
  // Replace these with authenticated user/device IDs when identity services
  // are implemented. They are recorded in audit and sync-outbox entries.
  static const _localActorId = 'local-owner';
  static const _localDeviceId = 'local-device';

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

  Future<void> _selectDestination(int value) async {
    final requiresOwnerAccess = value == 0 || value == 7;

    if (requiresOwnerAccess) {
      if (!OwnerAuthService.instance.isAuthenticated) {
        final granted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const OwnerAccessDialog(),
        );

        if (!mounted || granted != true) return;
      }
    } else {
      OwnerAuthService.instance.lock();
      _ownerSessionManager.cancel();
    }

    if (!mounted) return;

    setState(() => selected = value);
    _resetOwnerInactivityTimer();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;
    final page = _buildPage(selected);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (wide) {
      return _withActivityDetection(
        Scaffold(
          body: Row(
            children: [
              NavigationRail(
                extended: width >= 1150,
                selectedIndex: selected,
                onDestinationSelected: _selectDestination,
                leading: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 20, 12, 22),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.asset(
                          'assets/branding/sokopoa_icon.png',
                          width: 34,
                          height: 34,
                          fit: BoxFit.cover,
                        ),
                      ),
                      if (width >= 1150) ...[
                        const SizedBox(width: 10),
                        Text(
                          'SOKOPOA',
                          style: TextStyle(
                            color: colors.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 19,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                destinations: [
                  for (final item in items)
                    NavigationRailDestination(
                      icon: Icon(item.icon),
                      label: Text(item.label),
                    ),
                ],
              ),
              VerticalDivider(
                width: 1,
                color: theme.dividerTheme.color ??
                    theme.colorScheme.outlineVariant,
              ),
              Expanded(child: page),
            ],
          ),
        ),
      );
    }

    return _withActivityDetection(
      Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.asset(
                  'assets/branding/sokopoa_icon.png',
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'SOKOPOA',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Tooltip(
                message: 'Offline-first mode',
                child: Icon(
                  Icons.cloud_off_outlined,
                  color: AppTheme.amber,
                ),
              ),
            ),
          ],
        ),
        drawer: Drawer(
          child: SafeArea(
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.asset(
                          'assets/branding/sokopoa_icon.png',
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SOKOPOA',
                              style: TextStyle(
                                color: colors.primary,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'Wholesale management',
                              style: TextStyle(
                                color: theme.textTheme.bodySmall?.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                for (var i = 0; i < items.length; i++)
                  ListTile(
                    leading: Icon(items[i].icon),
                    title: Text(items[i].label),
                    selected: selected == i,
                    onTap: () async {
                      Navigator.pop(context);
                      await _selectDestination(i);
                    },
                  ),
              ],
            ),
          ),
        ),
        body: page,
      ),
    );
  }

  Widget _buildPage(int index) {
    if (index == 0) return const DashboardScreen();

    if (index == 1) {
      return const PosScreen(
        cashierUserId: _localActorId,
        deviceId: _localDeviceId,
      );
    }

    if (index == 2) {
      return const InventoryScreen(
        actorUserId: _localActorId,
        deviceId: _localDeviceId,
      );
    }

    if (index == 3) {
      return const CustomersScreen(
        actorUserId: _localActorId,
        deviceId: _localDeviceId,
      );
    }

    if (index == 4) {
      return const SuppliersScreen(
        actorUserId: _localActorId,
        deviceId: _localDeviceId,
      );
    }

    if (index == 5) {
      return const ExpensesScreen(
        actorUserId: _localActorId,
        deviceId: _localDeviceId,
      );
    }

    if (index == 6) {
      return const WorkersScreen(
        actorUserId: _localActorId,
        deviceId: _localDeviceId,
      );
    }

    if (index == 7) return const ReportsScreen();

    if (index == 8) return const NotificationsScreen();

    if (index == 9) return const SyncScreen();

    if (index == 10) return const AuditScreen();

    if (index == 11) {
      return _SettingsPage(themeController: widget.themeController);
    }

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
    '',
    'Fast checkout and payment recording.',
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
    <String>[],
    ['New sale'],
    ['Add product', 'Receive stock', 'Stocktake'],
    ['Add customer', 'Record payment'],
    ['Add supplier', 'Record purchase'],
    ['Record expense'],
    ['Add worker', 'Record payment'],
    ['Export report'],
    ['Review alerts'],
    ['Retry synchronization'],
    ['Export audit log'],
    ['Business profile'],
  ];

  static const _columns = [
    <String>[],
    ['Product search', 'Cart', 'Discount', 'Split payment', 'Receipt'],
    [
      'Code',
      'Category',
      'Buying cost',
      'Selling price',
      'Units',
      'Quantity',
      'Minimum stock',
    ],
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

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.themeController});

  final AppThemeController themeController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = themeController.themeMode == ThemeMode.dark;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Settings',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Manage your SOKOPOA application preferences.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 22),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isDark ? Icons.dark_mode_outlined : Icons.light_mode,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Appearance',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose the theme used throughout the application. '
                  'Your choice is saved on this device.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                  ],
                  selected: {themeController.themeMode},
                  onSelectionChanged: (selection) {
                    if (selection.isNotEmpty) {
                      themeController.setThemeMode(selection.first);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.storage_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Database & Data Ownership',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Create local JSON data exports or restore records. '
                  'The business owner retains full ownership of all database files.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          final backup = await BackupService().createBackupJson();
                          await Clipboard.setData(ClipboardData(text: backup));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Full database snapshot copied to clipboard!'),
                                backgroundColor: AppTheme.green,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Export error: $e'),
                                backgroundColor: AppTheme.danger,
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('Export JSON Snapshot'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon);

  final String label;
  final IconData icon;
}
