/// Offline QR verification (master spec section 34).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../app/service_locator.dart';
import '../../app/theme.dart';
import '../../models/evidence_record.dart';
import '../../security/hash_chain.dart';
import '../../security/hashing.dart';
import '../../services/qr_service.dart';
import '../../widgets/section_card.dart';
import '../result/record_detail_screen.dart';

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key});

  static const String route = '/verify';

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final MobileScannerController _scanner = MobileScannerController();

  QrPayload? _payload;
  EvidenceRecord? _local;
  RecordVerification? _verification;
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    unawaited(_scanner.dispose());
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || _payload != null) return;
    if (capture.barcodes.isEmpty) return;
    final String? raw = capture.barcodes.first.rawValue;
    if (raw == null) return;

    setState(() => _busy = true);
    try {
      final QrPayload? payload = QrPayload.decode(raw);
      if (payload == null) {
        setState(() => _message =
            'Scanned code is not a DruSight verification payload.');
        return;
      }

      final ServiceLocator services = context.read<ServiceLocator>();
      final EvidenceRecord? local =
          await services.evidence.findByTestId(payload.testId);

      RecordVerification? verification;
      if (local != null) {
        // The record exists on this device: run the full check, including
        // the chain link and the stored image.
        final List<EvidenceRecord> chain = await services.evidence.loadChain();
        final ChainVerification chainResult =
            await services.verification.verifyChain(
          chain,
          imageResolver: services.imageStorage.originalFileFor,
        );
        final Iterable<RecordVerification> matches = chainResult.perRecord
            .where((RecordVerification v) => v.testId == payload.testId);
        verification = matches.isEmpty ? null : matches.first;

        if (verification != null) {
          await services.evidence.recordVerification(
            verificationId:
                '${payload.testId}-${DateTime.now().microsecondsSinceEpoch}',
            testId: payload.testId,
            actorId: services.auth.currentSession?.account.operatorId,
            method: 'QR_SCAN',
            recordHashValid: verification.recordHashValid,
            linkValid: verification.linkValid,
            signatureValid: verification.signatureValid,
            imageHashValid: verification.imageHashValid,
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _payload = payload;
        _local = local;
        _verification = verification;
        _message = local == null
            ? 'This record was not created on this device. The payload can '
                'still be checked for internal consistency, but the original '
                'image and the chain position cannot be verified here.'
            : null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() => setState(() {
        _payload = null;
        _local = null;
        _verification = null;
        _message = null;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify record'),
        actions: <Widget>[
          if (_payload != null)
            IconButton(icon: const Icon(Icons.refresh), onPressed: _reset),
        ],
      ),
      body: _payload == null ? _scannerView() : _resultView(),
    );
  }

  Widget _scannerView() => Column(
        children: <Widget>[
          Expanded(
            child: MobileScanner(
              controller: _scanner,
              onDetect: _onDetect,
              // errorBuilder handles both permission-denied and hardware errors.
              // MobileScanner auto-requests permission when it first mounts —
              // we must NOT call controller.start() ourselves beforehand.
              errorBuilder: (
                BuildContext ctx,
                MobileScannerException error,
                Widget? child,
              ) {
                final bool isPermission =
                    error.errorCode == MobileScannerErrorCode.permissionDenied;
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          isPermission
                              ? Icons.camera_alt_outlined
                              : Icons.error_outline,
                          size: 56,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          isPermission
                              ? 'Camera permission required'
                              : 'Camera unavailable',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isPermission
                              ? 'Allow camera access in Settings → Apps → '
                                  'DruSight → Permissions, then tap Retry.'
                              : (error.errorDetails?.message ??
                                  error.errorCode.name),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () async {
                            await _scanner.stop();
                            await _scanner.start();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('RETRY'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                const Text(
                  'Scan a DruSight verification QR code.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  'Verification runs entirely on this device. No network '
                  'connection is used or required.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey.shade700,
                  ),
                ),
                if (_message != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    _message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: DruSightTheme.positive,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );

  Widget _resultView() {
    final QrPayload payload = _payload!;
    final RecordVerification? v = _verification;
    final bool knownLocally = _local != null;
    final bool intact = v?.intact ?? false;

    final Color colour = !knownLocally
        ? DruSightTheme.inconclusive
        : (intact ? DruSightTheme.negative : DruSightTheme.positive);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Container(
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
                !knownLocally
                    ? 'RECORD NOT HELD ON THIS DEVICE'
                    : (intact
                        ? 'CHAIN OF CUSTODY: VALID'
                        : 'CHAIN OF CUSTODY: BROKEN'),
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: colour,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                payload.testId,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Scanned payload',
          children: <Widget>[
            DataRow2('Format', payload.version),
            DataRow2('Record hash', payload.recordHash, monospace: true),
            DataRow2('Image hash', payload.imageHash, monospace: true),
            DataRow2('Previous hash', payload.previousRecordHash,
                monospace: true),
            DataRow2('Chain position', '${payload.sequenceNumber}'),
            DataRow2('Public key ID', payload.publicKeyId, monospace: true),
            DataRow2('Scheme', payload.signatureScheme),
            DataRow2('Created (UTC)', payload.createdAtUtc, monospace: true),
          ],
        ),
        const SizedBox(height: 12),
        if (knownLocally)
          SectionCard(
            title: 'Local verification',
            children: <Widget>[
              _check('Payload matches stored record',
                  Hashing.constantTimeEquals(
                      payload.recordHash, _local!.recordHash)),
              _check('Record hash', v?.recordHashValid),
              _check('Chain link', v?.linkValid),
              _check('Digital signature', v?.signatureValid),
              _check('Stored image', v?.imageHashValid),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        RecordDetailScreen(testId: payload.testId),
                  ),
                ),
                child: const Text('OPEN FULL EVIDENCE RECORD'),
              ),
            ],
          )
        else
          SectionCard(
            title: 'What can be checked here',
            children: <Widget>[
              Text(
                _message ?? '',
                style: const TextStyle(fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 10),
              const Text(
                'A verifier that also holds the issuing institution\'s public '
                'key registry could confirm the signing key belongs to that '
                'institution. This prototype has no such registry, so key '
                'ownership is not established.',
                style: TextStyle(fontSize: 12.5, height: 1.4),
              ),
            ],
          ),
        const SizedBox(height: 24),
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
              '$label: '
              '${ok == null ? "not checked" : (ok ? "VALID" : "INVALID")}',
              style: const TextStyle(fontSize: 13.5),
            ),
          ],
        ),
      );
}
