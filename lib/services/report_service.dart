/// Structured analysis report (master spec section 38).
///
/// Produces an ordered, section-by-section account of what happened. Every
/// value comes from a measurement or a stored field; nothing is narrated or
/// inferred.
library;

import '../config/app_config.dart';
import '../models/analysis_result.dart';
import '../models/evidence_record.dart';
import '../models/enums.dart';

class ReportSection {
  const ReportSection({required this.heading, required this.lines});
  final String heading;
  final List<String> lines;
}

class AnalysisReport {
  const AnalysisReport({required this.sections, required this.disclaimer});
  final List<ReportSection> sections;
  final String disclaimer;

  String toPlainText() {
    final StringBuffer out = StringBuffer();
    for (final ReportSection s in sections) {
      out.writeln(s.heading.toUpperCase());
      for (final String line in s.lines) {
        out.writeln('  $line');
      }
      out.writeln();
    }
    out.writeln(disclaimer);
    return out.toString();
  }
}

class ReportService {
  const ReportService();

  AnalysisReport build({
    required AnalysisResult analysis,
    required EvidenceRecord record,
    required bool recordHashValid,
    required bool signatureValid,
    required bool linkValid,
    required bool? imageHashValid,
  }) {
    return AnalysisReport(
      disclaimer: AppConfig.presumptiveDisclaimer,
      sections: <ReportSection>[
        ReportSection(
          heading: '1. What was captured',
          lines: <String>[
            'Test ID: ${record.testId}',
            'Kit: ${record.kitId} (profile ${record.kitProfileVersion})',
            'Image: ${analysis.quality.imageWidthPx} x '
                '${analysis.quality.imageHeightPx} px',
            'Reference card detected: '
                '${analysis.quality.referenceCardDetected ? "yes" : "no"}',
            if (analysis.trajectory.samples.isNotEmpty)
              'Timed sequence: ${analysis.trajectory.samples.length} frames',
          ],
        ),
        ReportSection(
          heading: '2. Capture quality',
          lines: <String>[
            'Sharpness (var. of Laplacian): '
                '${analysis.quality.blurVariance.toStringAsFixed(1)}',
            'Mean luminance: '
                '${analysis.quality.exposure.meanLuminance.toStringAsFixed(1)}',
            'Shadow-clipped: '
                '${(analysis.quality.exposure.shadowClippedFraction * 100).toStringAsFixed(2)}%',
            'Highlight-clipped: '
                '${(analysis.quality.exposure.highlightClippedFraction * 100).toStringAsFixed(2)}%',
            'Glare coverage: '
                '${(analysis.quality.glare.glareFraction * 100).toStringAsFixed(2)}%',
            'Capture accepted by guard: '
                '${analysis.quality.acceptable ? "yes" : "no"}',
          ],
        ),
        ReportSection(
          heading: '3. Reference-card calibration',
          lines: analysis.calibration.succeeded
              ? <String>[
                  'Status: fitted',
                  'Patches used: ${analysis.calibration.patchCount}',
                  'Mean residual dE2000: '
                      '${analysis.calibration.meanResidualDeltaE.toStringAsFixed(3)}',
                  'Max residual dE2000: '
                      '${analysis.calibration.maxResidualDeltaE.toStringAsFixed(3)}',
                  'Calibration version: ${record.calibrationVersion}',
                ]
              : <String>[
                  'Status: FAILED',
                  'Reason: ${analysis.calibration.failureReason}',
                  'No colour measurement was performed.',
                ],
        ),
        ReportSection(
          heading: '4. Colour measurements',
          lines: analysis.features == null
              ? <String>['No calibrated colour measurement was produced.']
              : <String>[
                  'Mean RGB: ${analysis.features!.meanRgb}',
                  'Mean HSV: ${analysis.features!.meanHsv}',
                  'Mean Lab: ${analysis.features!.meanLab}',
                  if (analysis.features!.deltaEFromReference != null)
                    'dE2000 from profile baseline: '
                        '${analysis.features!.deltaEFromReference!.toStringAsFixed(3)}',
                  'Spatial uniformity (mean tile dE2000): '
                      '${analysis.features!.spatialUniformity.toStringAsFixed(3)}',
                  'Pixels measured: ${analysis.features!.pixelCount}',
                ],
        ),
        ReportSection(
          heading: '5. Reaction pattern',
          lines: analysis.trajectory.isEmpty
              ? <String>[
                  'No timed sequence was captured for this kit profile.',
                ]
              : <String>[
                  'Frames: ${analysis.trajectory.samples.length}',
                  'Total dE2000: '
                      '${analysis.trajectory.totalDeltaE.toStringAsFixed(3)}',
                  'Net hue shift: '
                      '${analysis.trajectory.netHueShiftDegrees.toStringAsFixed(1)} deg',
                  'Largest step dE2000: '
                      '${analysis.trajectory.maxStepDeltaE.toStringAsFixed(3)}',
                  'Stabilised: ${analysis.trajectory.stabilised ? "yes" : "no"}',
                ],
        ),
        ReportSection(
          heading: '6. Model and algorithm versions',
          lines: <String>[
            'Algorithm: ${record.algorithmVersion}',
            'Feature schema: ${record.featureSchemaVersion}',
            'Calibration: ${record.calibrationVersion}',
            'Model: ${record.modelId ?? "none installed"} '
                '${record.modelVersion ?? ""}'.trim(),
            'Canonical format: ${record.canonicalFormatVersion}',
          ],
        ),
        ReportSection(
          heading: '7. Why this classification was produced',
          lines: analysis.explanation
              .map(
                (ExplanationItem e) =>
                    '${e.supportsResult ? "[+]" : "[-]"} ${e.statement}'
                    '${e.measurement != null ? " - ${e.measurement}" : ""}',
              )
              .toList(growable: false),
        ),
        ReportSection(
          heading: '8. Anomalies detected',
          lines: analysis.anomalies.isEmpty
              ? <String>['None.']
              : analysis.anomalies
                  .map((a) => '${a.code.wireName} (${a.severity.wireName}): '
                      '${a.detail}')
                  .toList(growable: false),
        ),
        ReportSection(
          heading: '9. Evidence integrity',
          lines: <String>[
            'Image SHA-256: ${record.imageHash}',
            'Record SHA-256: ${record.recordHash}',
            'Previous record SHA-256: ${record.previousRecordHash}',
            'Analysis digest: ${record.analysisDigest}',
            'Chain position: ${record.sequenceNumber}',
            'Record hash verifies: ${recordHashValid ? "YES" : "NO"}',
            'Chain link verifies: ${linkValid ? "YES" : "NO"}',
            'Stored image verifies: '
                '${imageHashValid == null ? "not checked" : (imageHashValid ? "YES" : "NO")}',
          ],
        ),
        ReportSection(
          heading: '10. Location',
          lines: record.location == null
              ? <String>[
                  'No location fix was available. Location is absent rather '
                      'than estimated.',
                ]
              : <String>[
                  'Latitude: ${record.location!.latitude}',
                  'Longitude: ${record.location!.longitude}',
                  'Accuracy: '
                      '${record.location!.accuracyMetres.toStringAsFixed(1)} m',
                  'Acquired: '
                      '${record.location!.acquiredAtUtc.toIso8601String()}',
                  if (record.location!.provider != null)
                    'Provider: ${record.location!.provider}',
                ],
        ),
        ReportSection(
          heading: '11. Timestamps',
          lines: <String>[
            'Capture (UTC): ${record.captureAtUtcIso}',
            'Record created (UTC): ${record.createdAtUtcIso}',
            'Record created (device local): ${record.createdAtLocalIso}',
            'Device UTC offset: '
                '${record.deviceTimeZoneOffsetMinutes} minutes',
            'Note: signing establishes that these values have not changed '
                'since the record was created. It does not establish the '
                'true wall-clock time of capture.',
          ],
        ),
        ReportSection(
          heading: '12. Digital signature',
          lines: <String>[
            'Scheme: ${record.signatureScheme}',
            'Public key ID: ${record.publicKeyId}',
            'Key version: ${record.keyVersion}',
            'Signature verifies: ${signatureValid ? "YES" : "NO"}',
          ],
        ),
        ReportSection(
          heading: '13. Chain of custody',
          lines: <String>[
            'Status: ${(recordHashValid && signatureValid && linkValid) ? "CHAIN OF CUSTODY: VALID" : "CHAIN OF CUSTODY: BROKEN"}',
          ],
        ),
        ReportSection(
          heading: '14. Result',
          lines: <String>[
            'Presumptive result: ${analysis.result.displayLabel}',
            'Reliability status: ${analysis.reliabilityStatus.displayLabel}',
            if (analysis.result == TestResult.inconclusive)
              'No presumptive positive or negative outcome is being reported '
                  'for this test.',
          ],
        ),
      ],
    );
  }
}
