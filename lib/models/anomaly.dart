/// A detected anomaly, carrying a machine-readable code plus the measured
/// evidence that triggered it (master spec section 27).
library;

import 'enums.dart';

class Anomaly {
  const Anomaly({
    required this.code,
    required this.severity,
    required this.detail,
    this.measuredValue,
    this.thresholdValue,
  });

  factory Anomaly.fromJson(Map<String, Object?> json) => Anomaly(
        code: AnomalyCode.fromWire(json['code']! as String) ??
            AnomalyCode.unsupportedCondition,
        severity: AnomalySeverity.values.firstWhere(
          (AnomalySeverity s) => s.wireName == json['severity'],
          orElse: () => AnomalySeverity.review,
        ),
        detail: json['detail']! as String,
        measuredValue: (json['measuredValue'] as num?)?.toDouble(),
        thresholdValue: (json['thresholdValue'] as num?)?.toDouble(),
      );

  final AnomalyCode code;
  final AnomalySeverity severity;

  /// Human-readable description of what was observed. Must describe a
  /// measurement, never a speculative cause.
  final String detail;

  /// The measurement and the threshold it violated, when the anomaly came
  /// from a numeric gate. Recorded so a reviewer can see how far out it was.
  final double? measuredValue;
  final double? thresholdValue;

  Map<String, Object?> toJson() => <String, Object?>{
        'code': code.wireName,
        'severity': severity.wireName,
        'detail': detail,
        'measuredValue': measuredValue,
        'thresholdValue': thresholdValue,
      };
}
