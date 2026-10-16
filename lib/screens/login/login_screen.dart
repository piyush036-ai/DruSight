/// Operator authentication screen (master spec section 8).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app.dart';
import '../../app/service_locator.dart';
import '../../app/theme.dart';
import '../../config/app_config.dart';
import '../../models/enums.dart';
import '../../repositories/audit_repository.dart';
import '../../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _officerId = TextEditingController();
  final TextEditingController _passphrase = TextEditingController();
  final TextEditingController _displayName = TextEditingController();

  bool _busy = false;
  bool _firstRun = false;
  String? _error;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFirstRun());
  }

  @override
  void dispose() {
    _officerId.dispose();
    _passphrase.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _checkFirstRun() async {
    final ServiceLocator services = context.read<ServiceLocator>();
    final int count = await services.operators.count();
    if (mounted) setState(() => _firstRun = count == 0);
  }

  /// Clears all operator accounts and the persisted session, then switches the
  /// screen into first-run / re-registration mode.
  Future<void> _resetPassphrase() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Reset passphrase?'),
        content: const Text(
          'This removes all operator accounts on this device. '
          'You will need to create a new account with a new passphrase. '
          'Test history and evidence records are kept.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('RESET'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ServiceLocator services = context.read<ServiceLocator>();
    try {
      await services.operators.deactivateAll();
      await services.auth.signOut();
      if (mounted) {
        setState(() {
          _firstRun = true;
          _officerId.clear();
          _passphrase.clear();
          _displayName.clear();
          _error = null;
        });
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = 'Reset failed: $e');
    }
  }

  Future<void> _submit() async {
    final ServiceLocator services = context.read<ServiceLocator>();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_firstRun) {
        await services.auth.register(
          officerId: _officerId.text,
          displayName: _displayName.text.isEmpty
              ? _officerId.text
              : _displayName.text,
          role: OperatorRole.administrator,
          passphrase: _passphrase.text,
        );
      }

      final AuthResult result = await services.auth.authenticate(
        officerId: _officerId.text,
        passphrase: _passphrase.text,
      );

      await services.audit.append(
        action: result.succeeded
            ? AuditAction.authenticated
            : AuditAction.authenticationFailed,
        actorId: result.session?.account.operatorId,
        subjectType: 'OPERATOR',
        subjectId: _officerId.text,
      );

      if (!mounted) return;
      if (result.succeeded) {
        await Navigator.of(context).pushReplacementNamed(HomeShell.route);
      } else {
        setState(() => _error = result.failureMessage);
      }
    } on ArgumentError catch (e) {
      setState(() => _error = e.message.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DruSightTheme.navy,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Icon(Icons.biotech, size: 56, color: Colors.white),
                  const SizedBox(height: 16),
                  const Text(
                    AppConfig.appName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    AppConfig.tagline,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 32),
                  Card(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            _firstRun
                                ? 'Create the first operator account'
                                : 'Operator sign-in',
                            style:
                                Theme.of(context).textTheme.titleMedium,
                          ),
                          if (_firstRun) ...<Widget>[
                            const SizedBox(height: 6),
                            Text(
                              'This device has no operator accounts yet. The '
                              'first account is created locally and given the '
                              'administrator role.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          TextField(
                            controller: _officerId,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Officer ID',
                            ),
                          ),
                          if (_firstRun) ...<Widget>[
                            const SizedBox(height: 12),
                            TextField(
                              controller: _displayName,
                              decoration: const InputDecoration(
                                labelText: 'Display name',
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passphrase,
                            obscureText: _obscure,
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Passphrase (minimum 8 characters)',
                              suffixIcon: IconButton(
                                icon: Icon(_obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                          ),
                          if (_error != null) ...<Widget>[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: DruSightTheme.positive,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: Text(
                              _busy
                                  ? 'Working...'
                                  : (_firstRun
                                      ? 'Create and sign in'
                                      : 'Sign in'),
                            ),
                          ),
                          if (!_firstRun) ...<Widget>[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _busy ? null : _resetPassphrase,
                              child: const Text(
                                'Forgot passphrase? Reset account',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            'Local device authentication for a field '
                            'prototype. This is not institutional identity '
                            'management and does not verify the officer ID '
                            'against any registry.',
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.4,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
