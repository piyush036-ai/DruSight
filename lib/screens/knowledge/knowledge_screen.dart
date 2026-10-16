/// Extensible Offline Substance & Test Knowledge Base
/// (master spec section 39).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/service_locator.dart';
import '../../repositories/knowledge_repository.dart';
import '../../widgets/section_card.dart';

class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({super.key});

  static const String route = '/knowledge';

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  final TextEditingController _search = TextEditingController();
  List<KnowledgeEntry> _entries = const <KnowledgeEntry>[];
  bool _syncing = false;
  String? _syncStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final List<KnowledgeEntry> entries = await context
        .read<ServiceLocator>()
        .knowledge
        .search(_search.text.trim());
    if (mounted) setState(() => _entries = entries);
  }

  Future<void> _syncNews() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _syncStatus = null;
    });
    try {
      final result =
          await context.read<ServiceLocator>().newsSync.sync();
      await _run();
      if (mounted) {
        setState(() {
          _syncStatus = result.fetched > 0
              ? 'Synced ${result.fetched} item(s)'
              : result.errors.isEmpty
                  ? 'No new items'
                  : 'Sync failed: ${result.errors.first}';
        });
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _syncStatus = 'Error: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Knowledge base'),
        actions: <Widget>[
          IconButton(
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download_outlined),
            tooltip: 'Sync live drug intelligence news',
            onPressed: _syncing ? null : _syncNews,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                TextField(
                  controller: _search,
                  onChanged: (_) => _run(),
                  decoration: const InputDecoration(
                    hintText: 'Search entries',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                ),
                if (_syncStatus != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    _syncStatus!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'Offline reference for presumptive field tests. '
                  'Tap ↓ to sync live NCB/UNODC drug intelligence news.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _entries.isEmpty
                ? const Center(child: Text('No entries match.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _entries.length,
                    itemBuilder: (_, int i) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _entryCard(_entries[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _entryCard(KnowledgeEntry e) => SectionCard(
        title: e.title,
        children: <Widget>[
          if (e.aliases.isNotEmpty)
            DataRow2('Also known as', e.aliases.join(', ')),
          if (e.classification != null)
            DataRow2('Classification', e.classification!),
          if (e.relatedKitIds.isNotEmpty)
            DataRow2('Related kits', e.relatedKitIds.join(', ')),
          const SizedBox(height: 10),
          ...e.sections.map(
            (KnowledgeSection s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    s.heading,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.body,
                    style: const TextStyle(fontSize: 13.5, height: 1.45),
                  ),
                ],
              ),
            ),
          ),
          if (e.safetyNotes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            const Text(
              'Safety',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 4),
            ...e.safetyNotes.map(
              (String s) => Text(
                '- $s',
                style: const TextStyle(fontSize: 13.5, height: 1.45),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Source: ${e.source} (${e.sourceVersion})'
            '${e.lastVerifiedDate != null ? " - last verified ${e.lastVerifiedDate}" : ""}',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
        ],
      );
}
