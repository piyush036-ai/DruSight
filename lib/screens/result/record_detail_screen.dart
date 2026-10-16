/// Full evidence record for a historical test, with live verification
/// (master spec sections 36, 38, 50).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/service_locator.dart';
import '../../app/theme.dart';
import '../../models/evidence_record.dart';
import '../../security/hash_chain.dart';
import '../../services/demo_tamper_service.dart';
import '../../services/qr_service.dart';
import '../../widgets/disclaimer_banner.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';

class RecordDetailScreen extends StatefulWidget {
  const RecordDetailScreen({required this.testId, super.key});

  final String testId;

  @override
  State<RecordDetailScreen> createState() => _RecordDetailScreenState();
}

class _RecordDetailScreenState extends State<RecordDetailScreen> {
  EvidenceRecord? _record;
  RecordVerification? _verification;
  Map<String, Object?>? _analysis;
  String? _imagePath;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final ServiceLocator services = context.read<ServiceLocator>();

    final EvidenceRecord? record =
        await services.evidence.findByTestId(widget.testId);
    final Map<String, Object?>? analysis =
        await services.tests.loadAnalysisJson(widget.testId);
    final File? image =
        await services.imageStorage.originalFileFor(widget.testId);

    RecordVerification? verification;
    if (record != null) {
      // Link validity requires the chain, so verify in chain context.
      final List<EvidenceRecord> chain = await services.evidence.loadChain();
      final ChainVerification chainResult =
          await services.verification.verifyChain(chain);
      verification = chainResult.perRecord.firstWhere(
        (RecordVerification v) => v.testId == widget.testId,
        orElse: () => RecordVerification(
          testId: widget.testId,
          sequenceNumber: record.sequenceNumber,
          recordHashValid: false,
          linkValid: false,
          signatureValid: false,
          imageHashValid: null,
          notes: const <String>['Record not present in the verified chain.'],
        ),
      );

      await services.evidence.recordVerification(
        verificationId:
            '${widget.testId}-${DateTime.now().microsecondsSinceEpoch}',
        testId: widget.testId,
        actorId: services.auth.currentSession?.account.operatorId,
        method: 'RECORD_DETAIL_OPEN',
        recordHashValid: verification.recordHashValid,
        linkValid: verification.linkValid,
        signatureValid: verification.signatureValid,
        imageHashValid: verification.imageHashValid,
      );
    }

    if (!mounted) return;
    setState(() {
      _record = record;
      _analysis = analysis;
      _verification = verification;
      _imagePath = image?.path;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ServiceLocator services = context.read<ServiceLocator>();
    final EvidenceRecord? record = _record;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Evidence record'),
        actions: <Widget>[
          if (services.demoTamper.enabled && record != null)
            IconButton(
              icon: const Icon(Icons.science_outlined),
              tooltip: 'Tamper demonstration',
              onPressed: () => _showTamperDemo(record),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : record == null
              ? const Center(child: Text('Record not found.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    _verdict(record),
                    const SizedBox(height: 16),
                    const DisclaimerBanner(),
                    const SizedBox(height: 16),
                    if (_imagePath != null) ...<Widget>[
                      SectionCard(
                        title: 'Original evidence image',
                        children: <Widget>[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(File(_imagePath!)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    _identity(record),
                    const SizedBox(height: 12),
                    _integrity(record),
                    const SizedBox(height: 12),
                    _timeAndPlace(record),
                    const SizedBox(height: 12),
                    _versions(record),
                    const SizedBox(height: 12),
                    _analysisCard(),
                    const SizedBox(height: 12),
                    SectionCard(
                      title: 'Verification QR',
                      children: <Widget>[
                        Center(
                          child: QrImageView(
                            data: QrPayload.fromRecord(record).encode(),
                            size: 180,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }

  Widget _verdict(EvidenceRecord record) {
    final RecordVerification? v = _verification;
    final bool intact = v?.intact ?? false;
    final Color colour =
        intact ? DruSightTheme.negative : DruSightTheme.positive;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.08),
        border: Border.all(color: colour, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            intact ? 'CHAIN OF CUSTODY: VALID' : 'CHAIN OF CUSTODY: BROKEN',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: colour,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              StatusChip.result(record.result),
              StatusChip.reliability(record.reliabilityStatus),
            ],
          ),
          if (v != null && v.notes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            ...v.notes.map(
              (String n) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  n,
                  style: TextStyle(fontSize: 13, color: colour, height: 1.35),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _identity(EvidenceRecord r) => SectionCard(
        title: 'Identity and context',
        children: <Widget>[
          DataRow2('Test ID', r.testId, monospace: true),
          DataRow2('Officer ID', r.officerId),
          DataRow2('Role', r.role.wireName),
          DataRow2('Session', r.sessionId, monospace: true),
          DataRow2('Device', '${r.deviceModel} (${r.osVersion})'),
          DataRow2('Device ID', r.deviceId, monospace: true),
          DataRow2('App version', r.appVersion),
          DataRow2('Kit', '${r.kitId} ${r.kitProfileVersion}'),
        ],
      );

  Widget _integrity(EvidenceRecord r) {
    final RecordVerification? v = _verification;
    return SectionCard(
      title: 'Integrity',
      children: <Widget>[
        DataRow2('Image SHA-256', r.imageHash, monospace: true),
        DataRow2('Record SHA-256', r.recordHash, monospace: true),
        DataRow2('Previous record', r.previousRecordHash, monospace: true),
        DataRow2('Analysis digest', r.analysisDigest, monospace: true),
        DataRow2('Chain position', '${r.sequenceNumber}'),
        const SizedBox(height: 8),
        _check('Record hash', v?.recordHashValid),
        _check('Chain link', v?.linkValid),
        _check('Digital signature', v?.signatureValid),
        _check('Stored image', v?.imageHashValid),
        const SizedBox(height: 8),
        DataRow2('Public key ID', r.publicKeyId, monospace: true),
        DataRow2('Key version', '${r.keyVersion}'),
        DataRow2('Scheme', r.signatureScheme),
      ],
    );
  }

  Widget _check(String label, bool? ok) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: <Widget>[
            Icon(
              ok == null
                  ? Icons.help_outline
                  : (ok ? Icons.check_circle : Icons.cancel),
              size: 18,
              color: ok == null
                  ? Colors.grey
                  : (ok ? DruSightTheme.negative : DruSightTheme.positive),
            ),
            const SizedBox(width: 8),
            Text(
              '$label: ${ok == null ? "not checked" : (ok ? "VALID" : "INVALID")}',
              style: const TextStyle(fontSize: 13.5),
            ),
          ],
        ),
      );

  Widget _timeAndPlace(EvidenceRecord r) => SectionCard(
        title: 'Time and location',
        children: <Widget>[
          DataRow2('Capture (UTC)', r.captureAtUtcIso, monospace: true),
          DataRow2('Created (UTC)', r.createdAtUtcIso, monospace: true),
          DataRow2('Created (local)', r.createdAtLocalIso, monospace: true),
          DataRow2('UTC offset', '${r.deviceTimeZoneOffsetMinutes} min'),
          const SizedBox(height: 8),
          if (r.location == null)
            const Text(
              'No location fix was available. Location is absent rather than '
              'estimated.',
              style: TextStyle(fontSize: 13, height: 1.35),
            )
          else ...<Widget>[
            DataRow2('Latitude', '${r.location!.latitude}', monospace: true),
            DataRow2('Longitude', '${r.location!.longitude}', monospace: true),
            DataRow2(
              'Accuracy',
              '${r.location!.accuracyMetres.toStringAsFixed(1)} m',
            ),
            DataRow2(
              'Acquired',
              r.location!.acquiredAtUtc.toIso8601String(),
              monospace: true,
            ),
          ],
        ],
      );

  Widget _versions(EvidenceRecord r) => SectionCard(
        title: 'Versions',
        children: <Widget>[
          DataRow2('Algorithm', r.algorithmVersion),
          DataRow2('Calibration', r.calibrationVersion),
          DataRow2('Feature schema', r.featureSchemaVersion),
          DataRow2('Model', r.modelId == null
              ? 'none installed at time of analysis'
              : '${r.modelId} ${r.modelVersion}'),
          DataRow2('Record format', r.canonicalFormatVersion),
        ],
      );

  Widget _analysisCard() {
    final Map<String, Object?>? analysis = _analysis;
    if (analysis == null) {
      return const SectionCard(
        title: 'Analysis',
        children: <Widget>[Text('Stored analysis not found.')],
      );
    }

    final List<Object?> explanation =
        (analysis['explanation'] ?? const <Object?>[]) as List<Object?>;

    return SectionCard(
      title: 'Recorded analysis',
      children: explanation.isEmpty
          ? <Widget>[const Text('No explanation was recorded.')]
          : explanation.map((Object? raw) {
              final Map<String, Object?> e = raw! as Map<String, Object?>;
              final bool supports = e['supportsResult'] == true;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      supports
                          ? Icons.check_circle_outline
                          : Icons.remove_circle_outline,
                      size: 17,
                      color: supports
                          ? DruSightTheme.negative
                          : DruSightTheme.inconclusive,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            e['statement']! as String,
                            style: const TextStyle(fontSize: 13.5, height: 1.35),
                          ),
                          if (e['measurement'] != null)
                            Text(
                              e['measurement']! as String,
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                                color: Colors.grey.shade700,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
    );
  }

  Future<void> _showTamperDemo(EvidenceRecord record) async {
    final ServiceLocator services = context.read<ServiceLocator>();

    final TamperScenario? scenario = await showDialog<TamperScenario>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Tamper demonstration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'This runs against an in-memory copy. The stored evidence '
              'record is not modified.',
              style: TextStyle(fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 12),
            ...TamperScenario.values.map(
              (TamperScenario s) => ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(s.label, style: const TextStyle(fontSize: 14)),
                onTap: () => Navigator.of(dialogContext).pop(s),
              ),
            ),
          ],
        ),
      ),
    );
    if (scenario == null || !mounted) return;

    final TamperDemoOutcome outcome = await services.demoTamper.demonstrate(
      record,
      scenario,
      actorId: services.auth.currentSession?.account.operatorId,
    );
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(outcome.failures.join(' + ')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Field changed: ${outcome.fieldChanged}'),
            const SizedBox(height: 8),
            SelectableText(
              'before: ${outcome.before}\nafter:  ${outcome.after}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
            ),
            const SizedBox(height: 12),
            const Text(
              'The stored record was not modified. Re-opening this record '
              'will verify as VALID.',
              style: TextStyle(fontSize: 12.5, height: 1.35),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }
}
