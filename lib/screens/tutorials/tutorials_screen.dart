/// Offline learning centre (master spec section 42).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../widgets/section_card.dart';

class TutorialsScreen extends StatefulWidget {
  const TutorialsScreen({super.key});

  static const String route = '/tutorials';

  @override
  State<TutorialsScreen> createState() => _TutorialsScreenState();
}

class _TutorialsScreenState extends State<TutorialsScreen> {
  List<Map<String, Object?>>? _lessons;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final Object? raw = jsonDecode(
      await rootBundle.loadString('assets/tutorials/tutorials.json'),
    );
    final List<Map<String, Object?>> lessons =
        ((raw! as Map<String, Object?>)['lessons']! as List<Object?>)
            .map((Object? l) => l! as Map<String, Object?>)
            .toList();
    if (mounted) setState(() => _lessons = lessons);
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, Object?>>? lessons = _lessons;
    return Scaffold(
      appBar: AppBar(title: const Text('Tutorials')),
      body: lessons == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Text(
                  'All tutorial content is stored on the device and is '
                  'available with no internet connection.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 14),
                for (final Map<String, Object?> lesson in lessons) ...<Widget>[
                  SectionCard(
                    title: lesson['title']! as String,
                    children: (lesson['steps']! as List<Object?>)
                        .map(
                          (Object? s) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const Text('- '),
                                Expanded(
                                  child: Text(
                                    s! as String,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 12),
              ],
            ),
    );
  }
}
