/// Kit library: every installed profile with its thresholds and provenance
/// (master spec sections 10, 43).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/service_locator.dart';
import '../../models/kit_profile.dart';
import '../../models/reference_card.dart';
import '../../widgets/section_card.dart';

class KitLibraryScreen extends StatefulWidget {
  const KitLibraryScreen({this.embedded = false, super.key});

  static const String route = '/kits';

  final bool embedded;

  @override
  State<KitLibraryScreen> createState() => _KitLibraryScreenState();
}

class _KitLibraryScreenState extends State<KitLibraryScreen> {
  List<KitProfile>? _kits;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final List<KitProfile> kits =
        await context.read<ServiceLocator>().kits.listLatest();
    if (mounted) setState(() => _kits = kits);
  }

  @override
  Widget build(BuildContext context) {
    final List<KitProfile>? kits = _kits;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kit library'),
        automaticallyImplyLeading: !widget.embedded,
      ),
      body: kits == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                for (final KitProfile k in kits) ...<Widget>[
                  _profileCard(k),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }

  Widget _profileCard(KitProfile k) => SectionCard(
        title: k.testName,
        children: <Widget>[
          DataRow2('Kit ID', k.kitId, monospace: true),
          DataRow2('Profile version', k.profileVersion),
          DataRow2('Manufacturer', k.manufacturer),
          DataRow2('Reagent type', k.reagentType),
          DataRow2('Last verified', k.lastVerifiedDate ?? 'not recorded'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              k.validationStatus,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: Color(0xFF5A3D00),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Quality thresholds',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 6),
          DataRow2('Min sharpness',
              k.qualityThresholds.minBlurVariance.toStringAsFixed(1)),
          DataRow2(
            'Max glare',
            '${(k.qualityThresholds.maxGlareFraction * 100).toStringAsFixed(2)}%',
          ),
          DataRow2(
            'Max calibration residual',
            'dE2000 '
                '${k.qualityThresholds.maxCalibrationResidualDeltaE.toStringAsFixed(2)}',
          ),
          DataRow2(
            'Min region quality',
            k.qualityThresholds.minRegionConfidence.toStringAsFixed(2),
          ),
          const SizedBox(height: 14),
          const Text(
            'Interpretation regions (CIE Lab centres)',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 6),
          ...k.decisionRegions.map(
            (ColourDecisionRegion r) => DataRow2(
              r.label,
              'L ${r.centreLab[0].toStringAsFixed(1)}, '
                  'a ${r.centreLab[1].toStringAsFixed(1)}, '
                  'b ${r.centreLab[2].toStringAsFixed(1)} '
                  '(radius ${r.radiusDeltaE.toStringAsFixed(1)}, '
                  'margin ${r.borderlineMarginDeltaE.toStringAsFixed(1)})',
              monospace: true,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Reference card',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 6),
          DataRow2('Card', '${k.referenceCard.cardId} '
              '${k.referenceCard.version}'),
          DataRow2('Patches', '${k.referenceCard.patches.length}'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: k.referenceCard.patches
                .map(
                  (ReferencePatch p) => Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Color.fromARGB(
                        255,
                        p.expectedSrgb.r.round(),
                        p.expectedSrgb.g.round(),
                        p.expectedSrgb.b.round(),
                      ),
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                )
                .toList(),
          ),
          if (k.referenceCard.printNotes != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              k.referenceCard.printNotes!,
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ],
        ],
      );
}
