import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/app_theme.dart';
import '../models/worker.dart';
import '../repositories/worker_repository.dart';

class WorkersScreen extends StatefulWidget {
  const WorkersScreen({
    super.key,
    required this.actorUserId,
    required this.deviceId,
    WorkerRepository? repository,
  }) : _repository = repository;

  final String actorUserId;
  final String deviceId;
  final WorkerRepository? _repository;

  @override
  State<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends State<WorkersScreen> {
  late final WorkerRepository _repository;

  final _searchController = TextEditingController();
  final _dateFormat = DateFormat('dd MMM yyyy');

  List<Worker> _workers = [];
  List<Worker> _allWorkers = [];

  bool _isLoading = true;
  String? _errorMessage;
  String _search = '';
  String _statusFilter = 'all';

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not provided';
    return _dateFormat.format(date.toLocal());
  }

  @override
  void initState() {
    super.initState();
    _repository = widget._repository ?? WorkerRepository();
    _loadWorkers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadWorkers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _repository.getWorkers(),
        _repository.getWorkers(
          search: _search,
          activeOnly: _statusFilter == 'all' ? null : _statusFilter == 'active',
        ),
      ]);

      if (!mounted) return;

      setState(() {
        _allWorkers = results[0];
        _workers = results[1];
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
    final activeCount = _allWorkers.where((worker) => worker.active).length;
    final inactiveCount = _allWorkers.length - activeCount;
    final pendingCount =
        _allWorkers.where((worker) => worker.syncState == 'pending').length;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadWorkers,
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
                              'Workers & payroll',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: theme.brightness == Brightness.dark
                                    ? colors.onSurface
                                    : AppTheme.navy,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Manage workers and monitor their records',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh workers',
                        onPressed: _loadWorkers,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: () => _showWorkerForm(),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Add worker'),
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
                        title: 'TOTAL WORKERS',
                        value: '${_allWorkers.length}',
                        subtitle: 'All registered workers',
                        icon: Icons.groups_outlined,
                        color: colors.primary,
                      ),
                      _summaryCard(
                        title: 'ACTIVE WORKERS',
                        value: '$activeCount',
                        subtitle: '$inactiveCount inactive',
                        icon: Icons.verified_user_outlined,
                        color: AppTheme.green,
                      ),
                      _summaryCard(
                        title: 'PENDING SYNC',
                        value: '$pendingCount',
                        subtitle: 'Waiting for synchronization',
                        icon: Icons.sync_outlined,
                        color: AppTheme.amber,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      _search = value;
                      _loadWorkers();
                    },
                    decoration: InputDecoration(
                      hintText: 'Search worker name, role or phone',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _searchController.clear();
                                _search = '';
                                _loadWorkers();
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: wide ? 240 : double.infinity,
                    child: DropdownButtonFormField<String>(
                      initialValue: _statusFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Worker status',
                        prefixIcon: Icon(Icons.filter_list),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('All workers'),
                        ),
                        DropdownMenuItem(
                          value: 'active',
                          child: Text('Active workers'),
                        ),
                        DropdownMenuItem(
                          value: 'inactive',
                          child: Text('Inactive workers'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => _statusFilter = value ?? 'all');
                        _loadWorkers();
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Worker records',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '${_workers.length} records',
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
                          'Could not load workers: $_errorMessage',
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                    )
                  else if (_workers.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.groups_outlined,
                                size: 42,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'No workers found',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Add a worker or change your search filters.',
                                textAlign: TextAlign.center,
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
                    ..._workers.map(_workerCard),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Deactivating a worker preserves their existing '
                              'sales history and records. Payroll payment '
                              'recording will be added separately.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
    required String value,
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
                  Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: colors.onSurface,
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

  Widget _workerCard(Worker worker) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusColor =
        worker.active ? AppTheme.green : colors.onSurfaceVariant;

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
            Icons.person_outline,
            color: colors.onPrimaryContainer,
          ),
        ),
        title: Text(
          worker.fullName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(worker.role),
              if (worker.phone?.isNotEmpty == true) Text(worker.phone!),
              const SizedBox(height: 4),
              Text(
                'Hired: ${_formatDate(worker.hiredAt)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 8,
                runSpacing: 5,
                children: [
                  _statusChip(
                    worker.active ? 'Active' : 'Inactive',
                    statusColor,
                  ),
                  _statusChip(
                    worker.syncState == 'pending' ? 'Pending sync' : 'Synced',
                    worker.syncState == 'pending'
                        ? AppTheme.amber
                        : AppTheme.green,
                  ),
                ],
              ),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Worker actions',
          onSelected: (value) {
            if (value == 'edit') {
              _showWorkerForm(worker: worker);
            } else if (value == 'status') {
              _confirmStatusChange(worker);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Edit details'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'status',
              child: ListTile(
                leading: Icon(
                  worker.active
                      ? Icons.person_off_outlined
                      : Icons.person_outline,
                ),
                title: Text(
                  worker.active ? 'Deactivate' : 'Reactivate',
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
          child: Icon(
            Icons.more_vert,
            color: colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _showWorkerForm({Worker? worker}) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(
      text: worker?.fullName ?? '',
    );
    final roleController = TextEditingController(
      text: worker?.role ?? '',
    );
    final phoneController = TextEditingController(
      text: worker?.phone ?? '',
    );

    DateTime? selectedHireDate = worker?.hiredAt?.toLocal();

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final theme = Theme.of(context);

            return AlertDialog(
              title: Text(
                worker == null ? 'Add worker' : 'Edit worker',
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
                        TextFormField(
                          controller: nameController,
                          autofocus: true,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Full name *',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Enter the worker full name.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: roleController,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Role *',
                            hintText: 'e.g. Cashier, Storekeeper',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Enter the worker role.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone number (optional)',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                        const SizedBox(height: 14),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.calendar_today_outlined),
                          title: const Text('Hire date'),
                          subtitle: Text(
                            selectedHireDate == null
                                ? 'Not provided'
                                : _formatDate(selectedHireDate),
                          ),
                          trailing: Wrap(
                            children: [
                              if (selectedHireDate != null)
                                IconButton(
                                  tooltip: 'Clear hire date',
                                  onPressed: () {
                                    setDialogState(
                                      () => selectedHireDate = null,
                                    );
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                              IconButton(
                                tooltip: 'Select hire date',
                                onPressed: () async {
                                  final now = DateTime.now();
                                  final picked = await showDatePicker(
                                    context: dialogContext,
                                    initialDate: selectedHireDate ?? now,
                                    firstDate: DateTime(now.year - 50),
                                    lastDate: DateTime(now.year + 1),
                                  );

                                  if (picked != null) {
                                    setDialogState(() {
                                      selectedHireDate = picked;
                                    });
                                  }
                                },
                                icon: const Icon(Icons.edit_calendar_outlined),
                              ),
                            ],
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
                FilledButton.icon(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      Navigator.pop(dialogContext, true);
                    }
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    worker == null ? 'Save worker' : 'Save changes',
                  ),
                ),
              ],
            );
          },
        ),
      );

      if (saved != true || !mounted) return;

      if (worker == null) {
        await _repository.createWorker(
          fullName: nameController.text,
          role: roleController.text,
          phone: phoneController.text,
          hiredAt: selectedHireDate,
          actorUserId: widget.actorUserId,
          deviceId: widget.deviceId,
        );
      } else {
        await _repository.updateWorker(
          workerId: worker.id,
          fullName: nameController.text,
          role: roleController.text,
          phone: phoneController.text,
          hiredAt: selectedHireDate,
          actorUserId: widget.actorUserId,
          deviceId: widget.deviceId,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            worker == null
                ? 'Worker added successfully.'
                : 'Worker details updated successfully.',
          ),
        ),
      );

      await _loadWorkers();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save worker: $error')),
      );
    } finally {
      nameController.dispose();
      roleController.dispose();
      phoneController.dispose();
    }
  }

  Future<void> _confirmStatusChange(Worker worker) async {
    final newStatus = !worker.active;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          newStatus ? 'Reactivate worker?' : 'Deactivate worker?',
        ),
        content: Text(
          newStatus
              ? 'Reactivate ${worker.fullName}? They will become available '
                  'for new POS transactions.'
              : 'Deactivate ${worker.fullName}? Their existing sales '
                  'history will be preserved, but they will no longer be '
                  'available for new POS transactions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(newStatus ? 'Reactivate' : 'Deactivate'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _repository.setWorkerActive(
        workerId: worker.id,
        active: newStatus,
        actorUserId: widget.actorUserId,
        deviceId: widget.deviceId,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus
                ? 'Worker reactivated successfully.'
                : 'Worker deactivated successfully.',
          ),
        ),
      );

      await _loadWorkers();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update worker status: $error')),
      );
    }
  }
}
