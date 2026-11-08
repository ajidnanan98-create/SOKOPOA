import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/app_theme.dart';
import '../../../data/local_database.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _filteredLogs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAuditLogs();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAuditLogs() async {
    try {
      final db = LocalDatabase.instance.db;
      final rows = await db.query(
        'audit_log',
        orderBy: 'occurred_at DESC',
        limit: 200,
      );
      if (mounted) {
        setState(() {
          _logs = rows;
          _filteredLogs = rows;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _filteredLogs = _logs);
      return;
    }

    setState(() {
      _filteredLogs = _logs.where((row) {
        final action = (row['action'] as String? ?? '').toLowerCase();
        final entity = (row['entity_type'] as String? ?? '').toLowerCase();
        final actor = (row['actor_user_id'] as String? ?? '').toLowerCase();
        return action.contains(query) || entity.contains(query) || actor.contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                child: const Icon(Icons.fact_check_outlined, color: AppTheme.navy, size: 26),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Immutable Audit Trail',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppTheme.navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Immutable, traceable record of all critical business transactions and modifications.',
                    style: TextStyle(color: AppTheme.textMuted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 22),

          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search audit records by user, action, or entity type...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      onPressed: () => _searchController.clear(),
                      icon: const Icon(Icons.clear),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 20),

          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_filteredLogs.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    _logs.isEmpty
                        ? 'No audit log entries recorded yet.'
                        : 'No audit records match your search query.',
                    style: const TextStyle(color: AppTheme.textMuted),
                  ),
                ),
              ),
            )
          else
            Card(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Timestamp', style: TextStyle(fontWeight: FontWeight.w800))),
                    DataColumn(label: Text('User / Actor', style: TextStyle(fontWeight: FontWeight.w800))),
                    DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.w800))),
                    DataColumn(label: Text('Entity Type', style: TextStyle(fontWeight: FontWeight.w800))),
                    DataColumn(label: Text('Entity ID', style: TextStyle(fontWeight: FontWeight.w800))),
                    DataColumn(label: Text('Details / Payload', style: TextStyle(fontWeight: FontWeight.w800))),
                  ],
                  rows: [
                    for (final log in _filteredLogs)
                      DataRow(
                        cells: [
                          DataCell(Text(
                            log['occurred_at'] as String? ?? '',
                            style: const TextStyle(fontSize: 12),
                          )),
                          DataCell(Chip(
                            label: Text(
                              log['actor_user_id'] as String? ?? 'system',
                              style: const TextStyle(fontSize: 11),
                            ),
                            backgroundColor: const Color(0xFFF0F4F8),
                            side: BorderSide.none,
                          )),
                          DataCell(Text(
                            log['action'] as String? ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          )),
                          DataCell(Text(log['entity_type'] as String? ?? '')),
                          DataCell(Text(
                            log['entity_id'] as String? ?? '—',
                            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                          )),
                          DataCell(
                            IconButton(
                              icon: const Icon(Icons.info_outline, size: 18),
                              onPressed: () => _showDetailsDialog(log),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showDetailsDialog(Map<String, dynamic> log) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Audit Record Details — ${log['action']}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('Log ID', log['id'] as String? ?? ''),
              _detailRow('Actor User ID', log['actor_user_id'] as String? ?? ''),
              _detailRow('Device ID', log['device_id'] as String? ?? ''),
              _detailRow('Entity Type', log['entity_type'] as String? ?? ''),
              _detailRow('Entity ID', log['entity_id'] as String? ?? ''),
              _detailRow('Timestamp', log['occurred_at'] as String? ?? ''),
              if (log['reason'] != null && (log['reason'] as String).isNotEmpty)
                _detailRow('Reason', log['reason'] as String),
              const SizedBox(height: 12),
              const Text('Payload / New Value:', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FA),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  log['new_value'] as String? ?? 'None',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
