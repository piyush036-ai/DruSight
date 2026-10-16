/// System integrity: whole-chain verification for evidence and audit records
/// (master spec sections 32, 44, 49).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/service_locator.dart';
import '../../app/theme.dart';
import '../../models/evidence_record.dart';
import '../../security/hash_chain.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';

class IntegrityScreen extends StatefulWidget {
  const IntegrityScreen({this.embedded = false, super.key});

  static const String route = '/integrity';

  final bool embedded;

  @override
  State<IntegrityScreen> createState() => _IntegrityScreenState();
}

class _IntegrityScreenState extends State<IntegrityScreen> {
  ChainVerification? _chain;
  bool? _auditIntact;
  String _head = '';
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final ServiceLocator services = context.read<ServiceLocator>();

    final List<EvidenceRecord> chain = await services.evidence.loadChain();
    final ChainVerification result = await services.verification.verifyChain(
      chain,
      imageResolver: services.imageStorage.originalFileFor,
    );
    final bool auditOk = await services.audit.verifyChain();
    final String head = await services.evidence.headHash();

    if (!mounted) return;
    setState(() {
      _chain = result;
      _auditIntact = auditOk;
      _head = head;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ChainVerification? chain = _chain;

    return Scaffold(
      appBar: AppBar(
        title: const Text('System integrity'),
        automaticallyImplyLeading: !widget.embedded,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _running ? null : _run,
          ),
        ],
      ),
      body: _running && chain == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                SectionCard(
                  title: 'Evidence hash chain',
                  trailing: chain == null
                      ? null
                      : StatusChip(
                          label: chain.intact
                              ? 'CHAIN OF CUSTODY: VALID'
                              : 'CHAIN OF CUSTODY: BROKEN',
                          colour: chain.intact
                              ? DruSightTheme.negative
                              : DruSightTheme.positive,
                        ),
                  children: <Widget>[
                    DataRow2('Records checked',
                        '${chain?.recordsChecked ?? 0}'),
                    DataRow2('Head hash', _head, monospace: true),
                    if (chain?.firstBreakSequence != null)
                      DataRow2(
                        'First break at sequence',
                        '${chain!.firstBreakSequence}',
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Each record commits to its predecessor, so modifying '
                      'any historical record invalidates that record and '
                      'every record after it. Signing establishes that a '
                      'record has not changed since creation; it does not '
                      'establish the true wall-clock time of capture.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'Audit trail',
                  trailing: _auditIntact == null
                      ? null
                      : StatusChip(
                          label: _auditIntact! ? 'INTACT' : 'BROKEN',
                          colour: _auditIntact!
                              ? DruSightTheme.negative
                              : DruSightTheme.positive,
                        ),
                  children: const <Widget>[
                    Text(
                      'Audit events are themselves hash-chained, so deleting '
                      'or editing one is detectable.',
                      style: TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (chain != null && chain.perRecord.isNotEmpty)
                  SectionCard(
                    title: 'Per-record verification',
                    children: chain.perRecord
                        .map(
                          (RecordVerification v) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  v.intact ? Icons.check_circle : Icons.cancel,
                                  size: 18,
                                  color: v.intact
                                      ? DruSightTheme.negative
                                      : DruSightTheme.positive,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '#${v.sequenceNumber}  ${v.testId}',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
