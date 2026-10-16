/// Result page (master spec sections 37, 38).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/service_locator.dart';
import '../../app/theme.dart';
import '../../models/analysis_result.dart';
import '../../models/anomaly.dart';
import '../../models/enums.dart';
import '../../models/kit_profile.dart';
import '../../security/hash_chain.dart';
import '../../services/qr_service.dart';
import '../../services/report_service.dart';
import '../../services/test_workflow_service.dart';
import '../../widgets/disclaimer_banner.dart';
import '../../widgets/reaction_graph.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({
    required this.completed,
    required this.profile,
    super.key,
  });

  final CompletedTest completed;
  final KitProfile profile;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  RecordVerification? _verification;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
  }

  Future<void> _verify() async {
    final ServiceLocator services = context.read<ServiceLocator>();
    final RecordVerification v = await services.verification.verifyRecord(
      widget.completed.record,
      imageFile: File(widget.completed.originalImagePath),
    );
    if (mounted) setState(() => _verification = v);
  }

  @override
  Widget build(BuildContext context) {
    final AnalysisResult analysis = widget.completed.analysis;
    final RecordVerification? v = _verification;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Test result'),
        automaticallyImplyLeading: false,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.home_outlined),
            onPressed: () =>
                Navigator.of(context).popUntil((Route<void> r) => r.isFirst),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _headline(analysis),
          const SizedBox(height: 16),
          const DisclaimerBanner(),
          const SizedBox(height: 16),
          _imageCard(),
          const SizedBox(height: 12),
          _explanationCard(analysis),
          const SizedBox(height: 12),
          _measurementsCard(analysis),
          const SizedBox(height: 12),
          if (!analysis.trajectory.isEmpty) ...<Widget>[
            SectionCard(
              title: 'Reaction fingerprint',
              children: <Widget>[
                ReactionGraph(trajectory: analysis.trajectory),
                const SizedBox(height: 12),
                Text(
                  'A reaction fingerprint is an additional evidence feature. '
                  'It describes how the observed colour changed over time and '
                  'is not, on its own, a chemical identification.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          _qualityCard(analysis),
          const SizedBox(height: 12),
          _anomaliesCard(analysis),
          const SizedBox(height: 12),
          _integrityCard(v),
          const SizedBox(height: 12),
          _qrCard(),
          const SizedBox(height: 12),
          _versionsCard(analysis),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _showFullReport,
            icon: const Icon(Icons.description_outlined),
            label: const Text('VIEW DETAILED ANALYSIS REPORT'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _headline(AnalysisResult analysis) {
    final Color colour = DruSightTheme.forResult(analysis.result);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.08),
        border: Border.all(color: colour, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            analysis.result.displayLabel,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: colour,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              StatusChip.reliability(analysis.reliabilityStatus),
              StatusChip(
                label: analysis.anomalies.isEmpty
                    ? 'NO ANOMALIES'
                    : '${analysis.anomalies.length} ANOMALIES',
                colour: analysis.anomalies.isEmpty
                    ? DruSightTheme.negative
                    : DruSightTheme.inconclusive,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(
            widget.completed.testId,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageCard() {
    final File file = File(widget.completed.originalImagePath);
    return SectionCard(
      title: 'Captured evidence image',
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: file.existsSync()
              ? Image.file(file, fit: BoxFit.contain)
              : const Text('Original image file is not available.'),
        ),
        const SizedBox(height: 10),
        Text(
          'The original capture is stored unmodified. Any derived image is '
          'saved as a separate artefact.',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
        ),
      ],
    );
  }

  Widget _explanationCard(AnalysisResult analysis) => SectionCard(
        title: 'Why this result',
        children: analysis.explanation
            .map(
              (ExplanationItem e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      e.supportsResult
                          ? Icons.check_circle_outline
                          : Icons.remove_circle_outline,
                      size: 18,
                      color: e.supportsResult
                          ? DruSightTheme.negative
                          : DruSightTheme.inconclusive,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            e.statement,
                            style: const TextStyle(fontSize: 14, height: 1.35),
                          ),
                          if (e.measurement != null)
                            Text(
                              e.measurement!,
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
              ),
            )
            .toList(),
      );

  Widget _measurementsCard(AnalysisResult analysis) => SectionCard(
        title: 'Calibrated colour measurements',
        children: analysis.features == null
            ? <Widget>[
                const Text(
                  'No calibrated colour measurement was produced, because '
                  'calibration or region detection did not succeed.',
                ),
              ]
            : <Widget>[
                DataRow2('RGB', analysis.features!.meanRgb.toString(),
                    monospace: true),
                DataRow2('HSV', analysis.features!.meanHsv.toString(),
                    monospace: true),
                DataRow2('CIE Lab', analysis.features!.meanLab.toString(),
                    monospace: true),
                if (analysis.features!.deltaEFromReference != null)
                  DataRow2(
                    'dE2000 from baseline',
                    analysis.features!.deltaEFromReference!
                        .toStringAsFixed(3),
                    monospace: true,
                  ),
                DataRow2(
                  'Spatial uniformity',
                  analysis.features!.spatialUniformity.toStringAsFixed(3),
                  monospace: true,
                ),
                DataRow2(
                  'Pixels measured',
                  '${analysis.features!.pixelCount}',
                  monospace: true,
                ),
              ],
      );

  Widget _qualityCard(AnalysisResult analysis) => SectionCard(
        title: 'Capture and calibration quality',
        children: <Widget>[
          DataRow2('Sharpness',
              analysis.quality.blurVariance.toStringAsFixed(1),
              monospace: true),
          DataRow2(
            'Glare coverage',
            '${(analysis.quality.glare.glareFraction * 100).toStringAsFixed(2)}%',
            monospace: true,
          ),
          DataRow2(
            'Mean luminance',
            analysis.quality.exposure.meanLuminance.toStringAsFixed(1),
            monospace: true,
          ),
          DataRow2(
            'Calibration',
            analysis.calibration.succeeded
                ? 'fitted, mean residual dE2000 '
                    '${analysis.calibration.meanResidualDeltaE.toStringAsFixed(3)}'
                : 'FAILED',
          ),
          if (analysis.region != null)
            DataRow2(
              'Region quality',
              '${analysis.region!.confidence.toStringAsFixed(2)} '
                  '(${analysis.region!.selectionMode.wireName})',
            ),
        ],
      );

  Widget _anomaliesCard(AnalysisResult analysis) => SectionCard(
        title: 'Anomalies',
        children: analysis.anomalies.isEmpty
            ? <Widget>[const Text('None detected.')]
            : analysis.anomalies
                .map(
                  (Anomaly a) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                a.code.wireName,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            StatusChip(
                              label: a.severity.wireName,
                              colour: switch (a.severity) {
                                AnomalySeverity.blocking =>
                                  DruSightTheme.positive,
                                AnomalySeverity.review =>
                                  DruSightTheme.inconclusive,
                                AnomalySeverity.informational =>
                                  DruSightTheme.blocked,
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          a.detail,
                          style: const TextStyle(fontSize: 13, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
      );

  Widget _integrityCard(RecordVerification? v) {
    final bool intact = v?.intact ?? false;
    return SectionCard(
      title: 'Evidence integrity',
      trailing: v == null
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : StatusChip(
              label: intact
                  ? 'CHAIN OF CUSTODY: VALID'
                  : 'CHAIN OF CUSTODY: BROKEN',
              colour:
                  intact ? DruSightTheme.negative : DruSightTheme.positive,
            ),
      children: <Widget>[
        DataRow2('Image SHA-256',
            widget.completed.record.imageHash, monospace: true),
        DataRow2('Record SHA-256',
            widget.completed.record.recordHash, monospace: true),
        DataRow2('Previous record',
            widget.completed.record.previousRecordHash, monospace: true),
        DataRow2('Chain position',
            '${widget.completed.record.sequenceNumber}'),
        DataRow2('Signature scheme',
            widget.completed.record.signatureScheme),
        DataRow2('Public key ID',
            widget.completed.record.publicKeyId, monospace: true),
        if (v != null && v.notes.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          ...v.notes.map(
            (String n) => Text(
              n,
              style: const TextStyle(
                fontSize: 13,
                color: DruSightTheme.positive,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _qrCard() => SectionCard(
        title: 'Verification QR',
        children: <Widget>[
          Center(
            child: QrImageView(
              data: QrPayload.fromRecord(widget.completed.record).encode(),
              size: 200,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Contains integrity values and version metadata only. No officer '
            'identity, location or substance information is encoded.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      );

  Widget _versionsCard(AnalysisResult analysis) => SectionCard(
        title: 'Versions recorded with this result',
        children: <Widget>[
          DataRow2('Kit profile',
              '${analysis.kitId} ${analysis.kitProfileVersion}'),
          DataRow2('Algorithm', analysis.algorithmVersion),
          DataRow2('Calibration', analysis.calibration.calibrationVersion),
          DataRow2(
            'Feature schema',
            analysis.features?.schemaVersion ?? 'not produced',
          ),
          DataRow2(
            'Model',
            analysis.classifierOutput.available
                ? '${analysis.classifierOutput.modelId} '
                    '${analysis.classifierOutput.modelVersion}'
                : 'none installed',
          ),
        ],
      );

  void _showFullReport() {
    final ServiceLocator services = context.read<ServiceLocator>();
    final RecordVerification? v = _verification;

    final AnalysisReport report = services.report.build(
      analysis: widget.completed.analysis,
      record: widget.completed.record,
      recordHashValid: v?.recordHashValid ?? false,
      signatureValid: v?.signatureValid ?? false,
      linkValid: v?.linkValid ?? false,
      imageHashValid: v?.imageHashValid,
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        builder: (_, ScrollController controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            Text('Detailed analysis report',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            ...report.sections.map(
              (ReportSection s) => Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      s.heading,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...s.lines.map(
                      (String l) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: SelectableText(
                          l,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const DisclaimerBanner(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
