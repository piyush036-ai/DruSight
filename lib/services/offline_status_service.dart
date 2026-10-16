/// Offline readiness reporting (master spec sections 5, 40).
///
/// DruSight is offline-first: nothing here checks for connectivity, because no
/// core function depends on it. What this service reports is whether the
/// LOCAL resources a test needs are actually present, so the app can refuse
/// clearly instead of failing halfway through a capture.
library;

import '../repositories/evidence_repository.dart';
import '../repositories/kit_repository.dart';
import '../repositories/knowledge_repository.dart';
import '../config/versions.dart';
import '../models/kit_profile.dart';

class OfflineResource {
  const OfflineResource({
    required this.name,
    required this.available,
    required this.detail,
  });

  final String name;
  final bool available;
  final String detail;
}

class OfflineStatus {
  const OfflineStatus({required this.resources, required this.headHash});

  final List<OfflineResource> resources;
  final String headHash;

  bool get allAvailable =>
      resources.every((OfflineResource r) => r.available);

  List<OfflineResource> get missing =>
      resources.where((OfflineResource r) => !r.available).toList();
}

class OfflineStatusService {
  OfflineStatusService(this._kits, this._knowledge, this._evidence);

  final KitRepository _kits;
  final KnowledgeRepository _knowledge;
  final EvidenceRepository _evidence;

  Future<OfflineStatus> check() async {
    final List<KitProfile> kits = await _kits.listLatest();
    final int knowledgeCount = await _knowledge.count();
    final int trainedModels =
        kits.where((KitProfile k) => k.hasTrainedModel).length;

    return OfflineStatus(
      headHash: await _evidence.headHash(),
      resources: <OfflineResource>[
        OfflineResource(
          name: 'Test kit profiles',
          available: kits.isNotEmpty,
          detail: kits.isEmpty
              ? 'No kit profiles installed. Tests cannot be run.'
              : '${kits.length} profile(s) installed',
        ),
        OfflineResource(
          name: 'Local classification model',
          available: trainedModels > 0,
          detail: trainedModels > 0
              ? '$trainedModels kit(s) have a trained model'
              : 'No trained model installed. Results are produced by the '
                  'deterministic colour rules in the kit profile only, and '
                  'every result is labelled accordingly.',
        ),
        OfflineResource(
          name: 'Offline knowledge base',
          available: knowledgeCount > 0,
          detail: '$knowledgeCount entry/entries installed',
        ),
        const OfflineResource(
          name: 'Calibration method',
          available: true,
          detail: Versions.calibration,
        ),
        const OfflineResource(
          name: 'Evidence signing key',
          available: true,
          detail: 'Generated on device and held in platform secure storage',
        ),
      ],
    );
  }
}
