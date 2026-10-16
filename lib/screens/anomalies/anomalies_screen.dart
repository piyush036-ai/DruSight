/// Anomaly overview and the human-review queue
/// (master spec sections 27, 50).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/service_locator.dart';
import '../../app/theme.dart';
import '../../models/enums.dart';
import '../../repositories/test_repository.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';
import '../result/record_detail_screen.dart';

class AnomaliesScreen extends StatefulWidget {
  const AnomaliesScreen({super.key});

  static const String route = '/anomalies';

  @override
  State<AnomaliesScreen> createState() => _AnomaliesScreenState();
}

class _AnomaliesScreenState extends State<AnomaliesScreen> {
  List<TestSummary> _reviewQueue = const <TestSummary>[];
  List<TestSummary> _flagged = const <TestSummary>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final ServiceLocator services = context.read<ServiceLocator>();
    final List<TestSummary> review = await services.tests.search(
      const HistoryQuery(
        reliabilityStatus: ReliabilityStatus.review,
        sort: HistorySort.newest,
        limit: 200,
      ),
    );
    final List<TestSummary> all = await services.tests.search(
      const HistoryQuery(sort: HistorySort.byAnomaly, limit: 200),
    );

    if (!mounted) return;
    setState(() {
      _reviewQueue = review;
      _flagged =
          all.where((TestSummary t) => t.anomalyCount > 0).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anomalies and review')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                SectionCard(
                  title: 'Review required',
                  trailing: StatusChip(
                    label: '${_reviewQueue.length}',
                    colour: DruSightTheme.inconclusive,
                  ),
                  children: <Widget>[
                    Text(
                      'A result is escalated for human review when a measured '
                      'value falls outside the kit profile\'s limits, when the '
                      'calibrated colour sits near a decision boundary, or '
                      'when the model and the profile rules disagree. A '
                      'reviewer can inspect the evidence and add notes; the '
                      'original machine result is never overwritten.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_reviewQueue.isEmpty)
                      const Text('No tests are awaiting review.')
                    else
                      ..._reviewQueue.map(_tile),
                  ],
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'Tests with recorded anomalies',
                  trailing: StatusChip(
                    label: '${_flagged.length}',
                    colour: DruSightTheme.positive,
                  ),
                  children: _flagged.isEmpty
                      ? <Widget>[const Text('None recorded.')]
                      : _flagged.map(_tile).toList(),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'Anomaly codes in this build',
                  children: AnomalyCode.values
                      .map(
                        (AnomalyCode c) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            c.wireName,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _tile(TestSummary t) => ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(
          t.testId,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
        subtitle: Text(
          '${t.kitId} - ${t.anomalyCount} anomaly/ies - '
          '${t.startedAtUtc.toLocal().toString().substring(0, 19)}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RecordDetailScreen(testId: t.testId),
          ),
        ),
      );
}
