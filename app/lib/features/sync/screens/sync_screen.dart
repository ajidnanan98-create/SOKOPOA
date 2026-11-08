import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/app_theme.dart';
import '../../../core/sync_service.dart';
import '../../../data/local_database.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final SyncService _syncService = SyncService.instance;
  List<Map<String, dynamic>> _outboxItems = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _syncService.addListener(_onSyncStateChanged);
    _loadOutboxItems();
  }

  @override
  void dispose() {
    _syncService.removeListener(_onSyncStateChanged);
    super.dispose();
  }

  void _onSyncStateChanged() {
    if (mounted) {
      setState(() {});
      _loadOutboxItems();
    }
  }

  Future<void> _loadOutboxItems() async {
    try {
      final db = LocalDatabase.instance.db;
      final rows = await db.query(
        'sync_outbox',
        orderBy: 'created_at DESC',
        limit: 100,
      );
      if (mounted) {
        setState(() {
          _outboxItems = rows;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _syncService.status;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
      case ConnectionStateStatus.online:
        statusColor = AppTheme.green;
        statusText = 'Online — Central server connected';
        statusIcon = Icons.cloud_done_outlined;
        break;
      case ConnectionStateStatus.syncing:
        statusColor = AppTheme.navy;
        statusText = 'Synchronizing pending outbox records...';
        statusIcon = Icons.sync;
        break;
      case ConnectionStateStatus.error:
        statusColor = AppTheme.danger;
        statusText = _syncService.lastError ?? 'Sync error occurred';
        statusIcon = Icons.cloud_off_outlined;
        break;
      case ConnectionStateStatus.offline:
      default:
        statusColor = AppTheme.amber;
        statusText = 'Offline-first mode — Queueing transactions locally';
        statusIcon = Icons.wifi_off_outlined;
        break;
    }

    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final lastSyncStr = _syncService.lastSyncTimestamp != null
        ? dateFormat.format(_syncService.lastSyncTimestamp!)
        : 'Not yet synchronized in this session';

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
                child: const Icon(Icons.sync, color: AppTheme.navy, size: 26),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Synchronization & Remote Queue',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppTheme.navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Monitor offline queue status, server connectivity, and trigger manual sync.',
                    style: TextStyle(color: AppTheme.textMuted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 22),

          // Status Banner Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: statusColor.withOpacity(0.4)),
            ),
            color: statusColor.withOpacity(0.06),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Last Successful Sync: $lastSyncStr',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.navy,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: status == ConnectionStateStatus.syncing
                        ? null
                        : () async {
                            final ok = await _syncService.triggerSync();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok ? 'Synchronization completed successfully' : 'Synchronization failed or offline',
                                  ),
                                  backgroundColor: ok ? AppTheme.green : AppTheme.danger,
                                ),
                              );
                            }
                          },
                    icon: status == ConnectionStateStatus.syncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.sync_outlined, size: 18),
                    label: const Text('Sync Now'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Outbox Metrics Row
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  title: 'Pending Queue',
                  value: '${_syncService.pendingCount}',
                  icon: Icons.hourglass_top_outlined,
                  color: AppTheme.amber,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _MetricCard(
                  title: 'Failed Records',
                  value: '${_syncService.failedCount}',
                  icon: Icons.error_outline_rounded,
                  color: AppTheme.danger,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _MetricCard(
                  title: 'Total Outbox Items',
                  value: '${_outboxItems.length}',
                  icon: Icons.outbox_outlined,
                  color: AppTheme.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Outbox Event Records',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.navy,
                ),
              ),
              if (_syncService.failedCount > 0)
                TextButton.icon(
                  onPressed: () => _syncService.retryFailedItems(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry Failed Items'),
                ),
            ],
          ),
          const SizedBox(height: 12),

          Card(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _outboxItems.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            'No sync outbox items recorded. All transactions are up to date.',
                            style: TextStyle(color: AppTheme.textMuted),
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          for (final item in _outboxItems) ...[
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _getStatusColor(item['status'] as String).withOpacity(0.15),
                                child: Icon(
                                  _getAggregateIcon(item['aggregate_type'] as String),
                                  color: _getStatusColor(item['status'] as String),
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                '${item['aggregate_type']?.toString().toUpperCase()} — ${item['event_type']}',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                'ID: ${item['id']}  •  Date: ${item['created_at']}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: Chip(
                                label: Text(
                                  (item['status'] as String).toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: _getStatusColor(item['status'] as String),
                                  ),
                                ),
                                backgroundColor: _getStatusColor(item['status'] as String).withOpacity(0.1),
                                side: BorderSide.none,
                              ),
                            ),
                            const Divider(height: 1),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'synced':
        return AppTheme.green;
      case 'failed':
        return AppTheme.danger;
      case 'pending':
      default:
        return AppTheme.amber;
    }
  }

  IconData _getAggregateIcon(String type) {
    switch (type) {
      case 'sale':
        return Icons.shopping_cart_outlined;
      case 'product':
        return Icons.inventory_2_outlined;
      case 'customer':
        return Icons.person_outlined;
      case 'supplier':
        return Icons.local_shipping_outlined;
      case 'expense':
        return Icons.receipt_long_outlined;
      case 'worker':
        return Icons.badge_outlined;
      default:
        return Icons.sync;
    }
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
