/// Guided capture screen (master spec sections 13, 14, 45).
///
/// Live preview with the region guide overlaid. The Smart Capture Guard runs
/// on downscaled preview frames so feedback is responsive; the final analysis
/// always runs on the full-resolution capture.
///
/// Calibration mode is chosen by the operator before capture:
///   • Built-in digital card — the 8-patch colour bar shown at the bottom of
///     the screen is used. No physical card is needed.
///   • Physical card — a second guide box appears on the camera view showing
///     where to place the physical printed reference card. The digital bar is
///     hidden. The operator must align the card inside the amber guide.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import '../../analysis/capture_guard.dart';
import '../../app/service_locator.dart';
import '../../app/theme.dart';
import '../../cv/region_detector.dart';
import '../../models/capture_quality.dart';
import '../../models/enums.dart';
import '../../models/kit_profile.dart';
import '../../models/test_region.dart';
import '../../services/test_workflow_service.dart';
import '../../widgets/capture_overlay.dart';
import '../../widgets/digital_card_bar.dart';
import '../result/result_screen.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    required this.profile,
    this.cardMode = ReferenceCardMode.builtin,
    super.key,
  });

  final KitProfile profile;

  /// Whether the operator will use the built-in digital card bar or place a
  /// physical printed reference card in the camera frame.
  final ReferenceCardMode cardMode;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  CaptureGuideGeometry get _geometry =>
      widget.cardMode == ReferenceCardMode.physical
          ? CaptureGuideGeometry.withPhysicalCard
          : CaptureGuideGeometry.standard;

  /// Preview frames are checked at this width. Small enough to stay responsive
  /// on a mid-range phone, large enough for the quality metrics to mean
  /// something.
  static const int _previewCheckWidth = 480;

  CameraController? _controller;
  Future<void>? _initialisation;
  final DateTime _startedAtUtc = DateTime.now().toUtc();

  CaptureQuality? _liveQuality;
  bool _checking = false;
  bool _processing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialisation = _setUpCamera();
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }

  Future<void> _setUpCamera() async {
    final List<CameraDescription> cameras = await availableCameras();
    if (cameras.isEmpty) {
      setState(() => _error = 'No camera is available on this device.');
      return;
    }
    final CameraDescription back = cameras.firstWhere(
      (CameraDescription c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final CameraController controller = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await controller.initialize();

    // Lock exposure and white balance once the operator has framed the shot:
    // auto-adjustment between preview and capture would change the very
    // quantity being measured.
    try {
      await controller.setFlashMode(FlashMode.off);
    } on CameraException {
      // Not fatal; some devices do not expose flash control.
    }

    if (!mounted) return;
    setState(() => _controller = controller);
  }

  /// Runs the guard on a still preview frame.
  Future<void> _checkFrame() async {
    final CameraController? controller = _controller;
    if (controller == null || _checking || _processing) return;

    setState(() => _checking = true);
    try {
      final XFile shot = await controller.takePicture();
      final Uint8List bytes = await shot.readAsBytes();
      final img.Image? full = img.decodeImage(bytes);
      if (full == null) return;

      final img.Image small = img.copyResize(full, width: _previewCheckWidth);
      final CaptureQuality quality = _evaluate(small);

      if (mounted) setState(() => _liveQuality = quality);
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = e.description);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  CaptureQuality _evaluate(img.Image image) {
    final RegionBox regionBox =
        _geometry.regionBoxIn(image.width, image.height);

    final RegionDetection region = const GuidedRegionDetector().detect(
      image,
      candidate: regionBox,
      mode: RegionSelectionMode.automatic,
    );

    return const CaptureGuard().evaluate(
      image,
      profile: widget.profile,
      regionDetection: region,
    );
  }

  Future<void> _capture() async {
    final CameraController? controller = _controller;
    if (controller == null || _processing) return;

    setState(() {
      _processing = true;
      _error = null;
    });

    // Resolved before the first await: reading an inherited widget after an
    // async gap risks touching a disposed element.
    final ServiceLocator services = context.read<ServiceLocator>();

    try {
      final DateTime captureAtUtc = DateTime.now().toUtc();
      final XFile shot = await controller.takePicture();
      final Uint8List bytes = await shot.readAsBytes();
      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) {
        setState(() => _error = 'Captured image could not be decoded.');
        return;
      }

      final CompletedTest completed =
          await TestWorkflowService(services).completeTest(
        profile: widget.profile,
        originalBytes: bytes,
        decoded: decoded,
        regionGuideBox:
            _geometry.regionBoxIn(decoded.width, decoded.height),
        regionMode: RegionSelectionMode.automatic,
        startedAtUtc: _startedAtUtc,
        captureAtUtc: captureAtUtc,
      );

      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ResultScreen(
            completed: completed,
            profile: widget.profile,
          ),
        ),
      );
    } on Exception catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.profile.testName),
        backgroundColor: Colors.black,
      ),
      body: FutureBuilder<void>(
        future: _initialisation,
        builder: (_, AsyncSnapshot<void> snapshot) {
          final CameraController? controller = _controller;
          if (_error != null) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (controller == null || !controller.value.isInitialized) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          final CaptureQuality? quality = _liveQuality;

          return Column(
            children: <Widget>[
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    CameraPreview(controller),
                    CaptureOverlay(
                      geometry: _geometry,
                      regionOk: quality?.testRegionDetected ?? false,
                      cardMode: widget.cardMode,
                    ),
                  ],
                ),
              ),
              _guidancePanel(quality),
            ],
          );
        },
      ),
    );
  }

  Widget _guidancePanel(CaptureQuality? quality) {
    final CaptureHint? hint = quality?.primaryHint;
    final bool acceptable = quality?.acceptable ?? false;

    return Container(
      width: double.infinity,
      color: Colors.black,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Digital reference card bar — shown only when using the built-in
          // card. Hidden when the operator chose a physical card.
          if (widget.cardMode == ReferenceCardMode.builtin)
            DigitalCardBar(spec: widget.profile.referenceCard),
          if (widget.cardMode == ReferenceCardMode.physical)
            _physicalCardReminder(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: acceptable
                        ? DruSightTheme.negative.withValues(alpha: 0.18)
                        : Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color:
                          acceptable ? DruSightTheme.negative : Colors.white24,
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        acceptable
                            ? Icons.check_circle
                            : Icons.info_outline,
                        color: acceptable
                            ? DruSightTheme.negative
                            : Colors.white70,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          hint?.message ??
                              'Place the reaction area inside the guide, '
                                  'then check the frame.',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _checking || _processing ? null : _checkFrame,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                        ),
                        icon: const Icon(Icons.rule),
                        label: Text(_checking ? 'Checking...' : 'CHECK FRAME'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        // Capture stays enabled even when the guard objects: the
                        // operator may need the record anyway. The analysis will
                        // report RECAPTURE REQUIRED rather than a result, so a
                        // poor capture cannot become a presumptive positive.
                        onPressed: _processing ? null : _capture,
                        icon: const Icon(Icons.camera),
                        label: Text(_processing ? 'ANALYSING...' : 'CAPTURE'),
                      ),
                    ),
                  ],
                ),
                if (quality != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    'sharpness ${quality.blurVariance.toStringAsFixed(0)} · '
                    'glare ${(quality.glare.glareFraction * 100).toStringAsFixed(1)}% · '
                    'luma ${quality.exposure.meanLuminance.toStringAsFixed(0)}',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 11.5),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Compact amber strip shown in place of the digital card bar when the
  /// operator is using a physical reference card.
  Widget _physicalCardReminder() {
    return Container(
      color: const Color(0xFF1A1400),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: const Row(
        children: <Widget>[
          Icon(Icons.style_outlined, color: Color(0xFFFFC107), size: 14),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Place the physical reference card flat inside the amber '
              'REFERENCE CARD guide.',
              style: TextStyle(
                color: Color(0xFFFFC107),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
