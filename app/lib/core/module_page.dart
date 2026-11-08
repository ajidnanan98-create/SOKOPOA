import 'package:flutter/material.dart';
import 'app_theme.dart';

class ModulePage extends StatefulWidget {
  const ModulePage({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.actions,
    this.columns = const [],
  });

  final String title;
  final String description;
  final IconData icon;
  final List<String> actions;
  final List<String> columns;

  @override
  State<ModulePage> createState() => _ModulePageState();
}

class _ModulePageState extends State<ModulePage> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF0F7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(widget.icon, color: AppTheme.navy, size: 25),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.navy)),
              const SizedBox(height: 4),
              Text(widget.description,
                style: const TextStyle(color: AppTheme.textMuted)),
            ],
          )),
        ]),
        const SizedBox(height: 22),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final action in widget.actions)
            FilledButton.tonalIcon(
              onPressed: () => _showPlannedAction(action),
              icon: const Icon(Icons.add, size: 18),
              label: Text(action),
            ),
        ]),
        const SizedBox(height: 18),
        TextField(
          controller: search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search ${widget.title.toLowerCase()}',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: search.text.isEmpty ? null : IconButton(
              onPressed: () { search.clear(); setState(() {}); },
              icon: const Icon(Icons.close),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.construction_outlined, color: AppTheme.amber),
                  SizedBox(width: 8),
                  Text('Module setup stage',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.navy)),
                ]),
                const SizedBox(height: 10),
                Text(
                  'The ${widget.title.toLowerCase()} workspace and navigation are in place. '
                  'The next implementation step connects this module to its local database, '
                  'validations, permissions and synchronization workflow.',
                  style: const TextStyle(height: 1.5, color: AppTheme.textMuted),
                ),
                if (widget.columns.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final col in widget.columns)
                      Chip(
                        label: Text(col),
                        backgroundColor: const Color(0xFFF1F4F8),
                        side: BorderSide.none,
                      ),
                  ]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showPlannedAction(String action) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(action),
        content: const Text(
          'This action is visible in the interface foundation. '
          'It will be enabled after the module database workflow is implemented '
          'and tested. No business record has been created.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }
}
