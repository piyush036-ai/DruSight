/// Searchable test history (master spec section 36).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/service_locator.dart';
import '../../models/enums.dart';
import '../../repositories/test_repository.dart';
import '../../widgets/status_chip.dart';
import '../result/record_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({this.embedded = false, super.key});

  static const String route = '/history';

  final bool embedded;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _search = TextEditingController();

  List<TestSummary> _results = const <TestSummary>[];
  bool _loading = true;

  TestResult? _result;
  ReliabilityStatus? _reliability;
  AnomalyCode? _anomaly;
  String? _kitId;
  DateTimeRange? _range;
  HistorySort _sort = HistorySort.newest;

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
    setState(() => _loading = true);
    final List<TestSummary> rows =
        await context.read<ServiceLocator>().tests.search(
              HistoryQuery(
                testIdContains: _search.text.trim().isEmpty
                    ? null
                    : _search.text.trim(),
                result: _result,
                reliabilityStatus: _reliability,
                anomalyCode: _anomaly,
                kitId: _kitId,
                from: _range?.start,
                to: _range?.end,
                sort: _sort,
                limit: 300,
              ),
            );
    if (mounted) {
      setState(() {
        _results = rows;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = Column(
      children: <Widget>[
        _filters(),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _results.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No tests match the current filters.'),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, int i) => _row(_results[i]),
                    ),
        ),
      ],
    );

    // `embedded` exists so the shell can suppress the back affordance when
    // this screen is a navigation destination rather than a pushed route.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test history'),
        automaticallyImplyLeading: !widget.embedded,
      ),
      body: body,
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: <Widget>[
          TextField(
            controller: _search,
            onSubmitted: (_) => _run(),
            decoration: InputDecoration(
              hintText: 'Search by test ID',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: _run,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                _dropdown<TestResult?>(
                  'Result',
                  _result,
                  <DropdownMenuItem<TestResult?>>[
                    const DropdownMenuItem<TestResult?>(
                      child: Text('Any result'),
                    ),
                    ...TestResult.values.map(
                      (TestResult r) => DropdownMenuItem<TestResult?>(
                        value: r,
                        child: Text(r.displayLabel),
                      ),
                    ),
                  ],
                  (TestResult? v) {
                    _result = v;
                    _run();
                  },
                ),
                const SizedBox(width: 8),
                _dropdown<ReliabilityStatus?>(
                  'Reliability',
                  _reliability,
                  <DropdownMenuItem<ReliabilityStatus?>>[
                    const DropdownMenuItem<ReliabilityStatus?>(
                      child: Text('Any reliability'),
                    ),
                    ...ReliabilityStatus.values.map(
                      (ReliabilityStatus s) =>
                          DropdownMenuItem<ReliabilityStatus?>(
                        value: s,
                        child: Text(s.displayLabel),
                      ),
                    ),
                  ],
                  (ReliabilityStatus? v) {
                    _reliability = v;
                    _run();
                  },
                ),
                const SizedBox(width: 8),
                _dropdown<AnomalyCode?>(
                  'Anomaly',
                  _anomaly,
                  <DropdownMenuItem<AnomalyCode?>>[
                    const DropdownMenuItem<AnomalyCode?>(
                      child: Text('Any anomaly'),
                    ),
                    ...AnomalyCode.values.map(
                      (AnomalyCode c) => DropdownMenuItem<AnomalyCode?>(
                        value: c,
                        child: Text(c.wireName),
                      ),
                    ),
                  ],
                  (AnomalyCode? v) {
                    _anomaly = v;
                    _run();
                  },
                ),
                const SizedBox(width: 8),
                _dropdown<HistorySort>(
                  'Sort',
                  _sort,
                  HistorySort.values
                      .map(
                        (HistorySort s) => DropdownMenuItem<HistorySort>(
                          value: s,
                          child: Text(s.name),
                        ),
                      )
                      .toList(),
                  (HistorySort? v) {
                    if (v != null) _sort = v;
                    _run();
                  },
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                  ),
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text(
                    _range == null
                        ? 'Any date'
                        : '${_range!.start.toIso8601String().substring(0, 10)} - '
                            '${_range!.end.toIso8601String().substring(0, 10)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown<T>(
    String hint,
    T value,
    List<DropdownMenuItem<T>> items,
    ValueChanged<T?> onChanged,
  ) =>
      DropdownButton<T>(
        value: value,
        hint: Text(hint, style: const TextStyle(fontSize: 13)),
        items: items,
        onChanged: onChanged,
        underline: const SizedBox.shrink(),
        style: const TextStyle(fontSize: 13, color: Colors.black87),
      );

  Future<void> _pickRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      _range = picked;
      await _run();
    }
  }

  Widget _row(TestSummary t) => ListTile(
        title: Text(
          t.testId,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
        ),
        subtitle: Text(
          '${t.kitId} - ${t.officerId} - '
          '${t.startedAtUtc.toLocal().toString().substring(0, 19)}'
          '${t.anomalyCount > 0 ? " - ${t.anomalyCount} anomaly/ies" : ""}',
          style: const TextStyle(fontSize: 12.5),
        ),
        trailing: t.result == null
            ? null
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  StatusChip.result(t.result!),
                ],
              ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RecordDetailScreen(testId: t.testId),
          ),
        ),
      );
}
