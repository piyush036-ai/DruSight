/// Extensible Offline Substance & Test Knowledge Base
/// (master spec section 39).
///
/// Named carefully: it is extensible and offline, and it makes no claim to
/// completeness. It contains only verified, authorised reference information
/// about presumptive tests, and explicitly no synthesis, extraction,
/// manufacture, concealment or use information.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../database/app_database.dart';

class KnowledgeEntry {
  const KnowledgeEntry({
    required this.entryId,
    required this.title,
    required this.aliases,
    required this.classification,
    required this.relatedKitIds,
    required this.sections,
    required this.safetyNotes,
    required this.source,
    required this.sourceVersion,
    required this.lastVerifiedDate,
  });

  factory KnowledgeEntry.fromJson(Map<String, Object?> json) {
    // Support both full entries (with sections) and lightweight news entries
    // (with a plain 'content' string and no sections list).
    final String? plainContent = json['content'] as String?;
    final List<KnowledgeSection> sections;
    if (plainContent != null && plainContent.isNotEmpty) {
      sections = <KnowledgeSection>[
        KnowledgeSection(heading: 'Summary', body: plainContent),
      ];
    } else {
      sections = ((json['sections'] ?? const <Object?>[]) as List<Object?>)
          .map((Object? s) =>
              KnowledgeSection.fromJson(s! as Map<String, Object?>))
          .toList(growable: false);
    }
    return KnowledgeEntry(
      entryId: json['entryId']! as String,
      title: json['title']! as String,
      aliases: ((json['aliases'] ?? const <Object?>[]) as List<Object?>)
          .map((Object? a) => a! as String)
          .toList(growable: false),
      classification: json['classification'] as String?,
      relatedKitIds:
          ((json['relatedKitIds'] ?? const <Object?>[]) as List<Object?>)
              .map((Object? k) => k! as String)
              .toList(growable: false),
      sections: sections,
      safetyNotes:
          ((json['safetyNotes'] ?? const <Object?>[]) as List<Object?>)
              .map((Object? s) => s! as String)
              .toList(growable: false),
      source: json['source']! as String,
      sourceVersion: json['sourceVersion']! as String,
      lastVerifiedDate: json['lastVerifiedDate'] as String?,
    );
  }

  final String entryId;
  final String title;
  final List<String> aliases;
  final String? classification;
  final List<String> relatedKitIds;
  final List<KnowledgeSection> sections;
  final List<String> safetyNotes;

  /// Where the content came from. Displayed with every entry so the reader can
  /// weigh it.
  final String source;
  final String sourceVersion;
  final String? lastVerifiedDate;

  Map<String, Object?> toJson() => <String, Object?>{
        'entryId': entryId,
        'title': title,
        'aliases': aliases,
        'classification': classification,
        'relatedKitIds': relatedKitIds,
        'sections': sections.map((KnowledgeSection s) => s.toJson()).toList(),
        'safetyNotes': safetyNotes,
        'source': source,
        'sourceVersion': sourceVersion,
        'lastVerifiedDate': lastVerifiedDate,
      };
}

class KnowledgeSection {
  const KnowledgeSection({required this.heading, required this.body});

  factory KnowledgeSection.fromJson(Map<String, Object?> json) =>
      KnowledgeSection(
        heading: json['heading']! as String,
        body: json['body']! as String,
      );

  final String heading;
  final String body;

  Map<String, Object?> toJson() =>
      <String, Object?>{'heading': heading, 'body': body};
}

class KnowledgeRepository {
  KnowledgeRepository(this._database);

  final AppDatabase _database;

  static const String manifestAsset = 'assets/knowledge/manifest.json';

  Future<void> installBundledEntries() async {
    final Object? manifest =
        jsonDecode(await rootBundle.loadString(manifestAsset));
    if (manifest is! Map<String, Object?>) return;

    for (final Object? file in manifest['entries']! as List<Object?>) {
      final Object? raw = jsonDecode(
        await rootBundle.loadString('assets/knowledge/${file! as String}'),
      );
      if (raw is! Map<String, Object?>) continue;
      final KnowledgeEntry entry = KnowledgeEntry.fromJson(raw);

      await _database.db.insert(
        'knowledge_base_entries',
        <String, Object?>{
          'entry_id': entry.entryId,
          'title': entry.title,
          'aliases': entry.aliases.join('|'),
          'classification': entry.classification,
          'related_kit_ids': entry.relatedKitIds.join('|'),
          'content_json': jsonEncode(entry.toJson()),
          'source': entry.source,
          'source_version': entry.sourceVersion,
          'last_verified_date': entry.lastVerifiedDate,
          'installed_at_utc': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<List<KnowledgeEntry>> search(String term) async {
    final String pattern = '%${term.replaceAll('%', '').replaceAll('_', '')}%';
    final List<Map<String, Object?>> rows = await _database.db.query(
      'knowledge_base_entries',
      where: term.isEmpty ? null : 'title LIKE ? OR aliases LIKE ?',
      whereArgs: term.isEmpty ? null : <Object?>[pattern, pattern],
      orderBy: 'title ASC',
    );
    return rows
        .map(
          (Map<String, Object?> r) => KnowledgeEntry.fromJson(
            jsonDecode(r['content_json']! as String) as Map<String, Object?>,
          ),
        )
        .toList(growable: false);
  }

  Future<int> count() async {
    final List<Map<String, Object?>> rows = await _database.db
        .rawQuery('SELECT COUNT(*) AS c FROM knowledge_base_entries');
    return (rows.first['c']! as num).toInt();
  }

  /// Upserts a live news item from the network sync service.
  /// Uses REPLACE conflict so the latest version of each entry wins.
  Future<void> upsertEntry(KnowledgeEntry entry) async {
    // Build a minimal toJson for news entries that may lack sections/safetyNotes.
    final Map<String, Object?> json = <String, Object?>{
      'entryId': entry.entryId,
      'title': entry.title,
      'aliases': entry.aliases,
      'classification': entry.classification,
      'relatedKitIds': entry.relatedKitIds,
      'sections': entry.sections.map((KnowledgeSection s) => s.toJson()).toList(),
      'safetyNotes': entry.safetyNotes,
      'source': entry.source,
      'sourceVersion': entry.sourceVersion,
      'lastVerifiedDate': entry.lastVerifiedDate,
      'content': entry.sections.isEmpty ? entry.title : null,
    };

    await _database.db.insert(
      'knowledge_base_entries',
      <String, Object?>{
        'entry_id': entry.entryId,
        'title': entry.title,
        'aliases': entry.aliases.join('|'),
        'classification': entry.classification,
        'related_kit_ids': entry.relatedKitIds.join('|'),
        'content_json': jsonEncode(json),
        'source': entry.source,
        'source_version': entry.sourceVersion,
        'last_verified_date': entry.lastVerifiedDate,
        'installed_at_utc': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns entries tagged as DRUG_INTELLIGENCE (live news items).
  Future<List<KnowledgeEntry>> listNewsEntries() async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'knowledge_base_entries',
      where: "classification = 'DRUG_INTELLIGENCE'",
      orderBy: 'installed_at_utc DESC',
      limit: 50,
    );
    return rows
        .map(
          (Map<String, Object?> r) => KnowledgeEntry.fromJson(
            jsonDecode(r['content_json']! as String) as Map<String, Object?>,
          ),
        )
        .toList(growable: false);
  }
}
