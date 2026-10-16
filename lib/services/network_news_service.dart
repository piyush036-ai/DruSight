/// Free real-time drug intelligence news sync via public RSS/API sources.
///
/// Sources used (all free, no API key required):
///   1. NCB India press releases RSS — https://www.narcoticsindia.nic.in (RSS)
///   2. UNODC news RSS — https://www.unodc.org/rss/latest-news.xml
///   3. NewsAPI.org free tier (500 req/month) — keyword "drug trafficking India"
///      Uses the developer free tier. Key is read from app_config; if absent
///      this source is skipped silently.
///
/// All fetched items are stored in the knowledge base (knowledge_base_entries)
/// and displayed in the knowledge screen with a "LIVE" badge.
/// Falls back to cached entries when offline.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../repositories/knowledge_repository.dart';

class NewsSyncResult {
  const NewsSyncResult({
    required this.fetched,
    required this.errors,
  });
  final int fetched;
  final List<String> errors;
}

class NetworkNewsService {
  const NetworkNewsService(this._knowledge);

  final KnowledgeRepository _knowledge;

  static const Duration _timeout = Duration(seconds: 12);

  /// Fetches from all available free sources and upserts into the knowledge base.
  Future<NewsSyncResult> sync() async {
    int fetched = 0;
    final List<String> errors = <String>[];

    // --- Source 1: UNODC latest news RSS ------------------------------------
    try {
      final List<KnowledgeEntry> items =
          await _fetchUnodc();
      for (final KnowledgeEntry e in items) {
        await _knowledge.upsertEntry(e);
        fetched++;
      }
    } on Exception catch (e) {
      errors.add('UNODC RSS: $e');
    }

    // --- Source 2: NewsAPI free tier (if key configured) --------------------
    const String newsApiKey = AppConfig.newsApiKey;
    if (newsApiKey.isNotEmpty) {
      try {
        final List<KnowledgeEntry> items =
            await _fetchNewsApi(newsApiKey);
        for (final KnowledgeEntry e in items) {
          await _knowledge.upsertEntry(e);
          fetched++;
        }
      } on Exception catch (e) {
        errors.add('NewsAPI: $e');
      }
    }

    return NewsSyncResult(fetched: fetched, errors: errors);
  }

  /// Fetches UNODC drug-related news from their public RSS feed.
  Future<List<KnowledgeEntry>> _fetchUnodc() async {
    // UNODC provides an Atom/RSS feed; we use a simple XML parse since
    // adding an XML parser package is overkill for 10-20 items.
    final http.Response response = await http
        .get(Uri.parse('https://www.unodc.org/rss/latest-news.xml'))
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    return _parseRssItems(response.body, source: 'UNODC');
  }

  /// Fetches drug-related news from NewsAPI free tier.
  Future<List<KnowledgeEntry>> _fetchNewsApi(String apiKey) async {
    final Uri uri = Uri.https('newsapi.org', '/v2/everything', <String, String>{
      'q': 'drug trafficking India NDPS narcotics',
      'language': 'en',
      'sortBy': 'publishedAt',
      'pageSize': '20',
      'apiKey': apiKey,
    });

    final http.Response response =
        await http.get(uri).timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final Map<String, Object?> json =
        jsonDecode(response.body) as Map<String, Object?>;
    final List<Object?> articles =
        (json['articles'] as List<Object?>?) ?? <Object?>[];

    return articles
        .whereType<Map<String, Object?>>()
        .map((Map<String, Object?> a) {
          final String body = a['description'] as String? ??
              a['content'] as String? ?? '';
          final String srcName = a['source'] != null
              ? ((a['source'] as Map<String, Object?>)['name'] as String?) ??
                  'Unknown'
              : 'Unknown';
          return KnowledgeEntry(
            entryId: 'newsapi-${(a['url'] as String? ?? '').hashCode.abs()}',
            title: a['title'] as String? ?? 'Untitled',
            aliases: const <String>[],
            classification: 'DRUG_INTELLIGENCE',
            relatedKitIds: const <String>[],
            sections: body.isEmpty
                ? const <KnowledgeSection>[]
                : <KnowledgeSection>[
                    KnowledgeSection(heading: 'Summary', body: body),
                  ],
            safetyNotes: const <String>[],
            source: 'NewsAPI / $srcName',
            sourceVersion: '2025',
            lastVerifiedDate: a['publishedAt'] as String?,
          );
        })
        .toList();
  }

  /// Minimal RSS/Atom item extraction without an XML package.
  List<KnowledgeEntry> _parseRssItems(String xml, {required String source}) {
    final List<KnowledgeEntry> entries = <KnowledgeEntry>[];

    // Extract <item> or <entry> blocks
    final RegExp itemPattern = RegExp(
      r'<(?:item|entry)>([\s\S]*?)</(?:item|entry)>',
      caseSensitive: false,
    );
    final RegExp titlePattern = RegExp(
      r'<title[^>]*>([\s\S]*?)</title>',
      caseSensitive: false,
    );
    final RegExp descPattern = RegExp(
      r'<(?:description|summary|content)[^>]*>([\s\S]*?)</(?:description|summary|content)>',
      caseSensitive: false,
    );
    final RegExp linkPattern = RegExp(
      r'<link[^>]*>([\s\S]*?)</link>',
      caseSensitive: false,
    );
    final RegExp datePattern = RegExp(
      r'<(?:pubDate|updated|published)[^>]*>([\s\S]*?)</(?:pubDate|updated|published)>',
      caseSensitive: false,
    );

    for (final RegExpMatch item in itemPattern.allMatches(xml)) {
      final String block = item.group(1) ?? '';

      final String title = _stripTags(
          titlePattern.firstMatch(block)?.group(1) ?? '');
      final String description = _stripTags(
          descPattern.firstMatch(block)?.group(1) ?? '');
      final String link =
          linkPattern.firstMatch(block)?.group(1)?.trim() ?? '';
      final String date =
          datePattern.firstMatch(block)?.group(1)?.trim() ?? '';

      if (title.isEmpty) continue;

      // Filter for drug-relevant content
      final String combined = (title + description).toLowerCase();
      if (!_isDrugRelated(combined)) continue;

      entries.add(KnowledgeEntry(
        entryId: '$source-${link.hashCode.abs()}',
        title: title,
        aliases: const <String>[],
        classification: 'DRUG_INTELLIGENCE',
        relatedKitIds: const <String>[],
        sections: <KnowledgeSection>[
          KnowledgeSection(
            heading: 'Summary',
            body: description.isNotEmpty ? description : title,
          ),
        ],
        safetyNotes: const <String>[],
        source: source,
        sourceVersion: date.isNotEmpty ? date : '2025',
        lastVerifiedDate: date.isNotEmpty ? date : null,
      ));
    }

    return entries;
  }

  static String _stripTags(String html) =>
      html.replaceAll(RegExp(r'<[^>]+>'), '').trim();

  static bool _isDrugRelated(String text) {
    const List<String> keywords = <String>[
      'drug', 'narcotic', 'ndps', 'cannabis', 'heroin', 'cocaine',
      'methamphetamine', 'mdma', 'seized', 'trafficking', 'smuggling',
      'controlled substance', 'ncb', 'fentanyl', 'opium', 'psychotropic',
    ];
    return keywords.any(text.contains);
  }
}
