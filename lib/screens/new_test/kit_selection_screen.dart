/// Test-kit selection and kit-specific instructions
/// (master spec section 45, steps 2-3).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/service_locator.dart';
import '../../app/theme.dart';
import '../../models/kit_profile.dart';
import '../../widgets/capture_overlay.dart';
import '../../widgets/section_card.dart';
import '../capture/capture_screen.dart';
import '../digital_card/digital_reference_card_screen.dart';

class KitSelectionScreen extends StatefulWidget {
  const KitSelectionScreen({super.key});

  @override
  State<KitSelectionScreen> createState() => _KitSelectionScreenState();
}

class _KitSelectionScreenState extends State<KitSelectionScreen> {
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
      appBar: AppBar(title: const Text('Select test kit')),
      body: kits == null
          ? const Center(child: CircularProgressIndicator())
          : kits.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No kit profiles are installed. A test cannot be run '
                    'without a kit profile, because the profile supplies the '
                    'reference-card specification, quality thresholds and '
                    'interpretation rules.',
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: kits.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, int i) => _kitCard(kits[i]),
                ),
    );
  }

  Widget _kitCard(KitProfile kit) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showInstructions(kit),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                kit.testName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${kit.manufacturer} - ${kit.reagentType}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _tag('${kit.kitId} ${kit.profileVersion}'),
                  _tag(
                    kit.hasTrainedModel
                        ? 'Model v${kit.modelVersion}'
                        : 'Colour-rule analysis',
                    warning: false,
                  ),
                  if (kit.reactionWindow.enabled)
                    _tag(
                      'Timed: ${kit.reactionWindow.captureOffsetsSeconds.join("s, ")}s',
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  kit.validationStatus,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: Color(0xFF5A3D00),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String label, {bool warning = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: warning
              ? DruSightTheme.inconclusive.withValues(alpha: 0.12)
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: warning
                ? const Color(0xFF7A5200)
                : Colors.grey.shade800,
          ),
        ),
      );

  void _showInstructions(KitProfile kit) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) =>
          _InstructionSheet(kit: kit, outerContext: context),
    );
  }
}

/// Bottom-sheet content for kit instructions + reference card mode selection.
/// Extracted into its own StatefulWidget so it can hold the [_cardMode] state
/// independently of the parent list screen.
class _InstructionSheet extends StatefulWidget {
  const _InstructionSheet({required this.kit, required this.outerContext});

  final KitProfile kit;

  /// The navigator context from the screen that owns the push routes. Using
  /// the sheet's own context for named routes leads to a "no route" error
  /// because the sheet is mounted on a different sub-tree.
  final BuildContext outerContext;

  @override
  State<_InstructionSheet> createState() => _InstructionSheetState();
}

class _InstructionSheetState extends State<_InstructionSheet> {
  ReferenceCardMode _cardMode = ReferenceCardMode.builtin;

  @override
  Widget build(BuildContext context) {
    final KitProfile kit = widget.kit;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      builder: (_, ScrollController controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(kit.testName,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Capture instructions',
            children: kit.captureInstructions
                .asMap()
                .entries
                .map(
                  (MapEntry<int, String> e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${e.key + 1}.',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(e.value)),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Safety',
            children: kit.safetyNotes
                .map(
                  (String s) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Icon(Icons.shield_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(s)),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          // ── Reference card selector ──────────────────────────────────────
          SectionCard(
            title: 'Reference card',
            children: <Widget>[
              const Text(
                'Choose how you will provide the colour reference for '
                'calibration.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              // Built-in option
              _CardModeOption(
                value: ReferenceCardMode.builtin,
                groupValue: _cardMode,
                title: 'Built-in digital card',
                subtitle:
                    'A colour bar is shown at the bottom of the camera '
                    'screen. No physical card needed.',
                icon: Icons.phone_android_outlined,
                onChanged: (ReferenceCardMode v) =>
                    setState(() => _cardMode = v),
              ),
              const SizedBox(height: 8),
              // Physical option
              _CardModeOption(
                value: ReferenceCardMode.physical,
                groupValue: _cardMode,
                title: 'Physical reference card',
                subtitle:
                    'Place your printed card inside the amber guide that '
                    'appears on the camera screen alongside the test region.',
                icon: Icons.style_outlined,
                onChanged: (ReferenceCardMode v) =>
                    setState(() => _cardMode = v),
              ),
              // If built-in is selected, offer to preview the digital card
              // on a second device.
              if (_cardMode == ReferenceCardMode.builtin) ...<Widget>[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(widget.outerContext)
                      .pushNamed(DigitalReferenceCardScreen.route),
                  icon: const Icon(Icons.palette_outlined),
                  label: const Text('OPEN DIGITAL CARD ON 2ND DEVICE'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(widget.outerContext).push(
                MaterialPageRoute<void>(
                  builder: (_) => CaptureScreen(
                    profile: kit,
                    cardMode: _cardMode,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('START CAPTURE'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// A single radio-style selection tile for the reference card mode.
class _CardModeOption extends StatelessWidget {
  const _CardModeOption({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onChanged,
  });

  final ReferenceCardMode value;
  final ReferenceCardMode groupValue;
  final String title;
  final String subtitle;
  final IconData icon;
  final ValueChanged<ReferenceCardMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final bool selected = value == groupValue;
    final Color accent = selected
        ? Theme.of(context).colorScheme.primary
        : Colors.grey.shade400;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06)
              : Colors.transparent,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, color: accent, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: selected ? accent : null,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: accent,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
