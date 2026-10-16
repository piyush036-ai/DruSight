/// Application shell and routing.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../screens/anomalies/anomalies_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/digital_card/digital_reference_card_screen.dart';
import '../screens/history/history_screen.dart';
import '../screens/integrity/integrity_screen.dart';
import '../screens/kit_library/kit_library_screen.dart';
import '../screens/knowledge/knowledge_screen.dart';
import '../screens/login/login_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/tutorials/tutorials_screen.dart';
import '../screens/verify/verify_screen.dart';
import 'service_locator.dart';
import 'theme.dart';

class DruSightApp extends StatelessWidget {
  const DruSightApp({required this.services, super.key});

  final ServiceLocator services;

  @override
  Widget build(BuildContext context) {
    // If a session was restored from secure storage (e.g. app was restarted
    // without signing out), land directly on the home shell — same behaviour
    // as Zomato, Swiggy, etc. where you stay logged in until you sign out or
    // uninstall.
    final Widget initialScreen = services.auth.currentSession != null
        ? const HomeShell()
        : const LoginScreen();

    return Provider<ServiceLocator>.value(
      value: services,
      child: MaterialApp(
        title: AppConfig.appName,
        theme: DruSightTheme.light(),
        debugShowCheckedModeBanner: false,
        home: initialScreen,
        routes: <String, WidgetBuilder>{
          HomeShell.route: (_) => const HomeShell(),
          HistoryScreen.route: (_) => const HistoryScreen(),
          KitLibraryScreen.route: (_) => const KitLibraryScreen(),
          TutorialsScreen.route: (_) => const TutorialsScreen(),
          AnomaliesScreen.route: (_) => const AnomaliesScreen(),
          KnowledgeScreen.route: (_) => const KnowledgeScreen(),
          IntegrityScreen.route: (_) => const IntegrityScreen(),
          SettingsScreen.route: (_) => const SettingsScreen(),
          VerifyScreen.route: (_) => const VerifyScreen(),
          DigitalReferenceCardScreen.route: (_) =>
              const DigitalReferenceCardScreen(),
        },
      ),
    );
  }
}

/// Bottom-navigation shell holding the four most-used destinations. The rest
/// are reachable from the dashboard, keeping the field-critical path short
/// (master spec section 43).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  static const String route = '/home';

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const List<Widget> _pages = <Widget>[
    DashboardScreen(),
    HistoryScreen(embedded: true),
    KitLibraryScreen(embedded: true),
    IntegrityScreen(embedded: true),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() => _index = i),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.science_outlined),
            selectedIcon: Icon(Icons.science),
            label: 'Kits',
          ),
          NavigationDestination(
            icon: Icon(Icons.verified_outlined),
            selectedIcon: Icon(Icons.verified),
            label: 'Integrity',
          ),
        ],
      ),
    );
  }
}
