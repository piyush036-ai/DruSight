/// Dashboard (master spec section 44).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/service_locator.dart';
import '../../app/theme.dart';
import '../../config/app_config.dart';
import '../../config/versions.dart';
import '../../models/enums.dart';
import '../../repositories/test_repository.dart';
import '../../services/offline_status_service.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';
import '../anomalies/anomalies_screen.dart';
import '../history/history_screen.dart';
import '../integrity/integrity_screen.dart';
import '../kit_library/kit_library_screen.dart';
import '../knowledge/knowledge_screen.dart';
import '../new_test/kit_selection_screen.dart';
import '../settings/settings_screen.dart';
import '../tutorials/tutorials_screen.dart';
import '../verify/verify_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  OfflineStatus? _status;
  List<TestSummary> _recent = const <TestSummary>[];
  int _pendingReviews = 0;
  int _anomalies = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final ServiceLocator services = context.read<ServiceLocator>();

    final OfflineStatus status = await services.offlineStatus.check();
    final List<TestSummary> recent = await services.tests.search(
      const HistoryQuery(limit: 5),
    );
    final List<TestSummary> review = await services.tests.search(
      const HistoryQuery(
        reliabilityStatus: ReliabilityStatus.review,
        limit: 200,
      ),
    );
    final List<TestSummary> all =
        await services.tests.search(const HistoryQuery(limit: 500));

    if (!mounted) return;
    setState(() {
      _status = status;
      _recent = recent;
      _pendingReviews = review.length;
      _anomalies =
          all.where((TestSummary t) => t.anomalyCount > 0).length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ServiceLocator services = context.read<ServiceLocator>();
    final String operator =
        services.auth.currentSession?.account.displayName ?? 'Operator';

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.appName),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Verify a record',
            onPressed: () =>
                Navigator.of(context).pushNamed(VerifyScreen.route),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () =>
                Navigator.of(context).pushNamed(SettingsScreen.route),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(
              'Signed in as $operator',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const KitSelectionScreen(),
                ),
              ),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('NEW TEST'),
            ),
            const SizedBox(height: 16),
            _offlineCard(),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: _counterCard(
                    'Pending reviews',
                    '$_pendingReviews',
                    Icons.rate_review_outlined,
                    DruSightTheme.inconclusive,
                    () => Navigator.of(context).pushNamed(HistoryScreen.route),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _counterCard(
                    'Tests with anomalies',
                    '$_anomalies',
                    Icons.warning_amber_outlined,
                    DruSightTheme.positive,
                    () =>
                        Navigator.of(context).pushNamed(AnomaliesScreen.route),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'Recent tests',
              trailing: TextButton(
                onPressed: () =>
                    Navigator.of(context).pushNamed(HistoryScreen.route),
                child: const Text('View all'),
              ),
              children: _recent.isEmpty
                  ? <Widget>[
                      const Text(
                        'No tests recorded on this device yet.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ]
                  : _recent
                      .map(
                        (TestSummary t) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(
                            t.testId,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            '${t.kitId} - '
                            '${t.startedAtUtc.toLocal()}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: t.result == null
                              ? null
                              : StatusChip.result(t.result!),
                        ),
                      )
                      .toList(),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'More',
              children: <Widget>[
                _navTile(Icons.science_outlined, 'Kit library',
                    KitLibraryScreen.route),
                _navTile(Icons.menu_book_outlined, 'Tutorials',
                    TutorialsScreen.route),
                _navTile(Icons.local_library_outlined,
                    'Offline knowledge base', KnowledgeScreen.route),
                _navTile(Icons.warning_amber_outlined, 'Anomalies',
                    AnomaliesScreen.route),
                _navTile(Icons.verified_outlined, 'System integrity',
                    IntegrityScreen.route),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Algorithm ${Versions.algorithm} - '
              'calibration ${Versions.calibration} - '
              'features ${Versions.featureSchema} - '
              'record format ${Versions.canonicalFormat}',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _offlineCard() {
    final OfflineStatus? status = _status;
    if (status == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Checking local resources...'),
        ),
      );
    }

    return SectionCard(
      title: 'Offline status',
      trailing: StatusChip(
        label: status.allAvailable ? 'READY OFFLINE' : 'PARTIAL',
        colour: status.allAvailable
            ? DruSightTheme.negative
            : DruSightTheme.inconclusive,
        icon: Icons.cloud_off,
      ),
      children: status.resources
          .map(
            (OfflineResource r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    r.available ? Icons.check_circle : Icons.error_outline,
                    size: 18,
                    color: r.available
                        ? DruSightTheme.negative
                        : DruSightTheme.inconclusive,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          r.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          r.detail,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _counterCard(
    String label,
    String value,
    IconData icon,
    Color colour,
    VoidCallback onTap,
  ) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: colour),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navTile(IconData icon, String label, String route) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).pushNamed(route),
      );
}
