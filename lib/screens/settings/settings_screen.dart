/// Settings and system information (master spec sections 43, 63).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/service_locator.dart';
import '../../app/theme.dart';
import '../../config/app_config.dart';
import '../../config/versions.dart';
import '../../database/app_database.dart';
import '../../models/device_identity.dart';
import '../../repositories/audit_repository.dart';
import '../../widgets/section_card.dart';
import '../digital_card/digital_reference_card_screen.dart';
import '../login/login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const String route = '/settings';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  DeviceIdentity? _device;
  List<AuditEvent> _audit = const <AuditEvent>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final ServiceLocator services = context.read<ServiceLocator>();
    final DeviceIdentity device = await services.deviceIdentity.current();
    final List<AuditEvent> audit = await services.audit.recent(limit: 40);
    if (mounted) {
      setState(() {
        _device = device;
        _audit = audit;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ServiceLocator services = context.read<ServiceLocator>();
    final DeviceIdentity? device = _device;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SectionCard(
            title: 'Signed-in operator',
            children: <Widget>[
              DataRow2(
                'Name',
                services.auth.currentSession?.account.displayName ?? '-',
              ),
              DataRow2(
                'Officer ID',
                services.auth.currentSession?.account.officerId ?? '-',
              ),
              DataRow2(
                'Role',
                services.auth.currentSession?.account.role.wireName ?? '-',
              ),
              DataRow2(
                'Session',
                services.auth.currentSession?.sessionId ?? '-',
                monospace: true,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  await services.audit.append(
                    action: AuditAction.signedOut,
                    actorId:
                        services.auth.currentSession?.account.operatorId,
                  );
                  await services.auth.signOut();
                  if (!context.mounted) return;
                  await Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute<void>(
                      builder: (_) => const LoginScreen(),
                    ),
                    (Route<void> r) => false,
                  );
                },
                icon: const Icon(Icons.logout),
                label: const Text('SIGN OUT'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Digital Reference Card',
            children: <Widget>[
              const Text(
                'Use your second phone or tablet as a software colour '
                'reference card — no printing required.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.of(context)
                    .pushNamed(DigitalReferenceCardScreen.route),
                icon: const Icon(Icons.palette_outlined),
                label: const Text('OPEN DIGITAL CARD'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Device',
            children: device == null
                ? <Widget>[const Text('Loading...')]
                : <Widget>[
                    DataRow2('Installation ID', device.installationId,
                        monospace: true),
                    DataRow2('Model', device.deviceModel),
                    DataRow2('OS', device.osVersion),
                    DataRow2('App', '${device.appVersion}+${device.appBuild}'),
                    const SizedBox(height: 8),
                    Text(
                      'The installation ID is a random value generated on this '
                      'device. No hardware serial, advertising ID or account '
                      'identifier is collected.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
          ),
          const SizedBox(height: 12),
          const SectionCard(
            title: 'Versions',
            children: <Widget>[
              DataRow2('Algorithm', Versions.algorithm),
              DataRow2('Calibration', Versions.calibration),
              DataRow2('Feature schema', Versions.featureSchema),
              DataRow2('Record format', Versions.canonicalFormat),
              DataRow2(
                'Database schema',
                '${AppConfig.databaseSchemaVersion}',
              ),
              DataRow2(
                'Demonstration mode',
                AppConfig.demoModeCompiledIn ? 'ENABLED' : 'disabled',
              ),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Reset device data',
            children: <Widget>[
              Text(
                'Clears all operator accounts, test history, and audit events '
                'from this device. Use this to reset a demo device before '
                'presenting. Evidence records and images are permanently deleted.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: DruSightTheme.positive,
                  side: const BorderSide(color: DruSightTheme.positive),
                ),
                onPressed: () => _confirmReset(context),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('RESET ALL DEVICE DATA'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Recent audit events',
            children: _audit.isEmpty
                ? <Widget>[const Text('No audit events recorded.')]
                : _audit
                    .map(
                      (AuditEvent e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          '${e.occurredAtUtc.toIso8601String()}  '
                          '${e.action}'
                          '${e.subjectId != null ? "  ${e.subjectId}" : ""}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                          ),
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

  Future<void> _confirmReset(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Reset all device data?'),
        content: const Text(
          'This permanently deletes all operator accounts, test history, '
          'evidence records, and audit events on this device. '
          'This cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: DruSightTheme.positive,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('DELETE EVERYTHING'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    // Read services before the async gap.
    final ServiceLocator services = context.read<ServiceLocator>();
    // Close the database and clear the session.
    await AppDatabase.closeInstance();
    await services.auth.signOut();

    if (!context.mounted) return;
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (Route<void> _) => false,
    );
  }
}
