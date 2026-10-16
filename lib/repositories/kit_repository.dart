/// Kit-profile loading and caching (master spec sections 10, 62).
///
/// Profiles ship as versioned JSON assets and are installed into SQLite on
/// first run so the searchable history can always resolve the exact profile
/// version a historical record was judged under, even after the bundled assets
/// change (master spec section 51).
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../database/app_database.dart';
import '../models/kit_profile.dart';

class KitRepository {
  KitRepository(this._database);

  final AppDatabase _database;
  final Map<String, KitProfile> _cache = <String, KitProfile>{};

  /// Asset manifest listing the kit profiles bundled with this build.
  static const String manifestAsset = 'assets/kits/manifest.json';

  /// Loads bundled profiles and upserts them into the database. Existing rows
  /// for the same (kit_id, profile_version) are left alone: an installed
  /// profile version is immutable by definition.
  Future<void> installBundledProfiles() async {
    final Object? manifest = jsonDecode(
      await rootBundle.loadString(manifestAsset),
    );
    if (manifest is! Map<String, Object?>) {
      throw const FormatException('Kit manifest is malformed.');
    }
    final List<Object?> files = manifest['profiles']! as List<Object?>;

    for (final Object? file in files) {
      final String path = 'assets/kits/${file! as String}';
      final Object? raw = jsonDecode(await rootBundle.loadString(path));
      if (raw is! Map<String, Object?>) continue;
      final KitProfile profile = KitProfile.fromJson(raw);

      final List<Map<String, Object?>> existing = await _database.db.query(
        'kit_profiles',
        where: 'kit_id = ? AND profile_version = ?',
        whereArgs: <Object?>[profile.kitId, profile.profileVersion],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        _cache['${profile.kitId}@${profile.profileVersion}'] = profile;
        continue;
      }

      await _database.db.insert('kit_profiles', <String, Object?>{
        'kit_id': profile.kitId,
        'profile_version': profile.profileVersion,
        'manufacturer': profile.manufacturer,
        'test_name': profile.testName,
        'reagent_type': profile.reagentType,
        'validation_status': profile.validationStatus,
        'profile_json': jsonEncode(profile.toJson()),
        'installed_at_utc': DateTime.now().toUtc().toIso8601String(),
      });
      _cache['${profile.kitId}@${profile.profileVersion}'] = profile;
    }
  }

  /// Latest installed version of each kit, for the kit library and selection
  /// screens.
  Future<List<KitProfile>> listLatest() async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery('''
      SELECT p.profile_json
      FROM kit_profiles p
      JOIN (
        SELECT kit_id, MAX(installed_at_utc) AS latest
        FROM kit_profiles
        GROUP BY kit_id
      ) newest
      ON p.kit_id = newest.kit_id AND p.installed_at_utc = newest.latest
      ORDER BY p.test_name ASC
    ''');
    return rows
        .map((Map<String, Object?> r) => KitProfile.fromJson(
              jsonDecode(r['profile_json']! as String) as Map<String, Object?>,
            ))
        .toList(growable: false);
  }

  /// Resolves an exact profile version. Used when re-opening a historical
  /// record, so it is always explained under the rules it was judged by.
  Future<KitProfile?> findExact(String kitId, String profileVersion) async {
    final KitProfile? cached = _cache['$kitId@$profileVersion'];
    if (cached != null) return cached;

    final List<Map<String, Object?>> rows = await _database.db.query(
      'kit_profiles',
      columns: <String>['profile_json'],
      where: 'kit_id = ? AND profile_version = ?',
      whereArgs: <Object?>[kitId, profileVersion],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final KitProfile profile = KitProfile.fromJson(
      jsonDecode(rows.first['profile_json']! as String) as Map<String, Object?>,
    );
    _cache['$kitId@$profileVersion'] = profile;
    return profile;
  }
}
