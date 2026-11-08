import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/app_theme.dart';
import '../../../data/local_database.dart';

class NotificationItem {
  NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.category,
    required this.severity,
    required this.timestamp,
    this.acknowledged = false,
  });

  final String id;
  final String title;
  final String message;
  final String category; // stock, sync, debt, worker, system
  final String severity; // info, warning, danger
  final DateTime timestamp;
  bool acknowledged;
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationItem> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    final list = <NotificationItem>[];
    final db = LocalDatabase.instance.db;

    try {
      // 1. Check Out of Stock and Low Stock Products
      final productRows = await db.rawQuery('''
        SELECT id, name, minimum_quantity,
          COALESCE((SELECT SUM(quantity_base) FROM stock_movements WHERE product_id = products.id), 0) AS balance
        FROM products
        WHERE active = 1
      ''');

      for (final p in productRows) {
        final name = p['name'] as String;
        final minQty = (p['minimum_quantity'] as num).toDouble();
        final balance = (p['balance'] as num).toDouble();

        if (balance <= 0) {
          list.add(
            NotificationItem(
              id: 'stock-out-${p['id']}',
              title: 'Out of Stock Alert: $name',
              message: 'Current balance is 0. Immediately reorder or restock from suppliers.',
              category: 'stock',
              severity: 'danger',
              timestamp: DateTime.now(),
            ),
          );
        } else if (balance <= minQty) {
          list.add(
            NotificationItem(
              id: 'stock-low-${p['id']}',
              title: 'Low Stock Warning: $name',
              message: 'Current balance is $balance (Min threshold: $minQty). Restock recommended.',
              category: 'stock',
              severity: 'warning',
              timestamp: DateTime.now(),
            ),
          );
        }
      }

      // 2. Check Pending Sync Items
      final syncRows = await db.rawQuery("SELECT COUNT(*) as count FROM sync_outbox WHERE status = 'pending'");
      final pendingCount = (syncRows.first['count'] as num).toInt();

      if (pendingCount > 10) {
        list.add(
          NotificationItem(
            id: 'sync-queue-warning',
            title: 'High Offline Sync Queue',
            message: 'You have $pendingCount offline transactions queued for cloud synchronization.',
            category: 'sync',
            severity: 'warning',
            timestamp: DateTime.now(),
          ),
        );
      }

      // 3. System status notification
      list.add(
        NotificationItem(
          id: 'system-ready',
          title: 'SOKOPOA Application Active',
          message: 'Offline-first database ledger initialized securely.',
          category: 'system',
          severity: 'info',
          timestamp: DateTime.now(),
        ),
      );

      if (mounted) {
        setState(() {
          _notifications = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _acknowledge(String id) {
    setState(() {
      for (final item in _notifications) {
        if (item.id == id) {
          item.acknowledged = true;
          break;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unackCount = _notifications.where((n) => !n.acknowledged).length;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF0F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.notifications_none, color: AppTheme.navy, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notifications & Business Alerts',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.navy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$unackCount active alert${unackCount == 1 ? '' : 's'} requiring administrator review.',
                      style: const TextStyle(color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_notifications.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: const [
                    Icon(Icons.check_circle_outline, size: 48, color: AppTheme.green),
                    SizedBox(height: 12),
                    Text(
                      'All Business Systems Operating Normally',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'No low stock, sync failures, or overdue accounts detected.',
                      style: TextStyle(color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: [
                for (final notif in _notifications) ...[
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: notif.acknowledged
                            ? Colors.grey.withOpacity(0.2)
                            : _getSeverityColor(notif.severity).withOpacity(0.4),
                      ),
                    ),
                    color: notif.acknowledged
                        ? Colors.grey.withOpacity(0.04)
                        : _getSeverityColor(notif.severity).withOpacity(0.05),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _getCategoryIcon(notif.category),
                            color: notif.acknowledged
                                ? AppTheme.textMuted
                                : _getSeverityColor(notif.severity),
                            size: 26,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        notif.title,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: notif.acknowledged
                                              ? AppTheme.textMuted
                                              : AppTheme.navy,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      DateFormat('HH:mm').format(notif.timestamp),
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  notif.message,
                                  style: TextStyle(
                                    color: notif.acknowledged
                                        ? AppTheme.textMuted
                                        : theme.textTheme.bodyMedium?.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (!notif.acknowledged)
                            TextButton.icon(
                              onPressed: () => _acknowledge(notif.id),
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('Acknowledge'),
                            )
                          else
                            const Chip(
                              label: Text('Acknowledged', style: TextStyle(fontSize: 10)),
                              backgroundColor: Color(0xFFEEEEEE),
                              side: BorderSide.none,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity) {
      case 'danger':
        return AppTheme.danger;
      case 'warning':
        return AppTheme.amber;
      case 'info':
      default:
        return AppTheme.navy;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'stock':
        return Icons.inventory_2_outlined;
      case 'sync':
        return Icons.sync_problem_outlined;
      case 'worker':
        return Icons.badge_outlined;
      case 'system':
      default:
        return Icons.info_outline;
    }
  }
}
