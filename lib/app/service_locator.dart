/// Composition root (master spec section 69).
///
/// Every dependency is constructed once, here. Screens receive services from
/// this object rather than reaching for globals, which is what makes the
/// classifier swappable and the whole pipeline testable.
library;

import '../analysis/analysis_pipeline.dart';
import '../database/app_database.dart';
import '../location/location_integrity.dart';
import '../location/location_service.dart';
import '../ml/classifier_service.dart';
import '../ml/onnx_classifier_service.dart';
import '../repositories/audit_repository.dart';
import '../repositories/evidence_repository.dart';
import '../repositories/kit_repository.dart';
import '../repositories/knowledge_repository.dart';
import '../repositories/operator_repository.dart';
import '../repositories/test_repository.dart';
import '../security/key_store.dart';
import '../security/signer.dart';
import '../services/auth_service.dart';
import '../services/demo_tamper_service.dart';
import '../services/device_identity_service.dart';
import '../services/evidence_service.dart';
import '../services/image_storage_service.dart';
import '../services/network_news_service.dart';
import '../services/offline_status_service.dart';
import '../services/report_service.dart';
import '../services/verification_service.dart';

class ServiceLocator {
  ServiceLocator._({
    required this.database,
    required this.operators,
    required this.kits,
    required this.tests,
    required this.evidence,
    required this.audit,
    required this.knowledge,
    required this.auth,
    required this.deviceIdentity,
    required this.imageStorage,
    required this.evidenceService,
    required this.verification,
    required this.pipeline,
    required this.classifier,
    required this.location,
    required this.locationIntegrity,
    required this.offlineStatus,
    required this.report,
    required this.demoTamper,
    required this.newsSync,
  });

  /// Builds the graph.
  ///
  /// [classifierOverride] exists so integration tests can inject a stub, and
  /// so swapping [MockClassifierService] for a real ONNX service is a
  /// one-line change here rather than an edit across the codebase.
  static Future<ServiceLocator> bootstrap({
    ClassifierService? classifierOverride,
    SigningKeyStore? keyStoreOverride,
    String? databasePath,
  }) async {
    final AppDatabase database =
        await AppDatabase.open(overridePath: databasePath);

    final OperatorRepository operators = OperatorRepository(database);
    final KitRepository kits = KitRepository(database);
    final TestRepository tests = TestRepository(database);
    final EvidenceRepository evidence = EvidenceRepository(database);
    final AuditRepository audit = AuditRepository(database);
    final KnowledgeRepository knowledge = KnowledgeRepository(database);

    final SigningKeyStore keyStore =
        keyStoreOverride ?? SecureStorageKeyStore();
    final EvidenceSigner signer = EvidenceSigner(keyStore);
    final VerificationService verification = VerificationService(signer);

    final ClassifierService classifier =
        classifierOverride ?? OnnxClassifierService();

    final AuthService authService = AuthService(operators);
    await authService.restoreSession();

    return ServiceLocator._(
      database: database,
      operators: operators,
      kits: kits,
      tests: tests,
      evidence: evidence,
      audit: audit,
      knowledge: knowledge,
      auth: authService,
      deviceIdentity: DeviceIdentityService(),
      imageStorage: ImageStorageService(),
      evidenceService: EvidenceService(signer),
      verification: verification,
      pipeline: AnalysisPipeline(classifier: classifier),
      classifier: classifier,
      location: const GeolocatorLocationService(),
      locationIntegrity: const LocationIntegrityChecker(),
      offlineStatus: OfflineStatusService(kits, knowledge, evidence),
      report: const ReportService(),
      demoTamper: DemoTamperService(verification, audit),
      newsSync: NetworkNewsService(knowledge),
    );
  }

  final AppDatabase database;
  final OperatorRepository operators;
  final KitRepository kits;
  final TestRepository tests;
  final EvidenceRepository evidence;
  final AuditRepository audit;
  final KnowledgeRepository knowledge;
  final AuthService auth;
  final DeviceIdentityService deviceIdentity;
  final ImageStorageService imageStorage;
  final EvidenceService evidenceService;
  final VerificationService verification;
  final AnalysisPipeline pipeline;
  final ClassifierService classifier;
  final LocationService location;
  final LocationIntegrityChecker locationIntegrity;
  final OfflineStatusService offlineStatus;
  final ReportService report;
  final DemoTamperService demoTamper;
  final NetworkNewsService newsSync;

  /// Installs bundled kit profiles and knowledge entries. Safe to call on
  /// every launch: existing versions are left untouched.
  Future<void> installBundledContent() async {
    await kits.installBundledProfiles();
    await knowledge.installBundledEntries();
  }
}
