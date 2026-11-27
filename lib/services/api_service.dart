import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/scan_entry.dart';

class ApiSendResult {
  final bool success;
  final int statusCode;
  final String message;
  final String responseBody;

  const ApiSendResult({
    required this.success,
    required this.statusCode,
    required this.message,
    required this.responseBody,
  });
}

class ApiService {
  static const String _legacyConfigKey = 'snaplog_ocr_api_config_v1';
  static const String _storeKey = 'snaplog_ocr_api_store_v2';

  Future<ApiStore> loadStore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawStore = prefs.getString(_storeKey);
      if (rawStore != null && rawStore.isNotEmpty) {
        return ApiStore.fromJson(jsonDecode(rawStore) as Map<String, dynamic>);
      }

      // Migrate legacy single-API config if present
      final legacyRaw = prefs.getString(_legacyConfigKey);
      if (legacyRaw != null && legacyRaw.isNotEmpty) {
        final legacy =
            ApiConfig.fromJson(jsonDecode(legacyRaw) as Map<String, dynamic>);
        if (legacy.isConfigured) {
          final migrated = legacy.copyWith(
            id: generateRandomIdString(length: 8, prefix: 'api_'),
            name: 'API Utama',
            customFields: legacy.customFields.isEmpty
                ? defaultApiFields()
                : legacy.customFields,
          );
          final store = ApiStore(profiles: [migrated], activeId: migrated.id);
          await saveStore(store);
          return store;
        }
      }
    } catch (_) {}
    return const ApiStore();
  }

  Future<void> saveStore(ApiStore store) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storeKey, jsonEncode(store.toJson()));
  }

  Future<ApiConfig?> loadActiveConfig() async {
    final store = await loadStore();
    return store.activeProfile;
  }

  /// Adds a new profile or updates an existing one by ID.
  /// If [setActive] is true (or this is the first profile), it becomes the only active API.
  Future<ApiStore> upsertProfile(
    ApiConfig profile, {
    bool setActive = false,
  }) async {
    final store = await loadStore();
    final id = profile.id.trim().isEmpty
        ? generateRandomIdString(length: 8, prefix: 'api_')
        : profile.id;
    final normalized = profile.copyWith(id: id);

    final nextList = List<ApiConfig>.from(store.profiles);
    final idx = nextList.indexWhere((p) => p.id == id);
    if (idx >= 0) {
      nextList[idx] = normalized;
    } else {
      nextList.add(normalized);
    }

    final shouldActivate = setActive || store.profiles.isEmpty;
    final nextStore = ApiStore(
      profiles: nextList,
      activeId: shouldActivate ? id : store.activeId,
    );
    await saveStore(nextStore);
    return nextStore;
  }

  /// Sets exactly ONE active API profile (pass null to deactivate all / offline mode).
  Future<ApiStore> setActiveProfile(String? profileId) async {
    final store = await loadStore();
    final validId = (profileId != null &&
            store.profiles.any((p) => p.id == profileId))
        ? profileId
        : null;
    final nextStore = store.copyWith(
      activeId: validId,
      clearActive: validId == null,
    );
    await saveStore(nextStore);
    return nextStore;
  }

  Future<ApiStore> deleteProfile(String profileId) async {
    final store = await loadStore();
    final nextList = store.profiles.where((p) => p.id != profileId).toList();
    final nextActive = store.activeId == profileId ? null : store.activeId;
    final nextStore = ApiStore(
      profiles: nextList,
      activeId: nextActive,
    );
    await saveStore(nextStore);
    return nextStore;
  }

  /// Builds dynamic payload map from [config.customFields].
  /// Supports scanValue, randomString (ID generator), staticValue (with template tokens),
  /// timestamp, scanType, and note.
  Map<String, dynamic> buildPayload(
    ScanEntry entry,
    ApiConfig config, {
    String Function(String prefix)? randomGenerator,
  }) {
    final gen = randomGenerator ??
        (prefix) => generateRandomIdString(length: 10, prefix: prefix);

    if (config.customFields.isEmpty) {
      return entry.toApiPayload();
    }

    final payload = <String, dynamic>{};
    for (final field in config.customFields) {
      final key = field.key.trim();
      if (key.isEmpty) continue;

      switch (field.type) {
        case ApiFieldType.scanValue:
          payload[key] = entry.text;
          break;
        case ApiFieldType.randomString:
          payload[key] = gen(field.value);
          break;
        case ApiFieldType.timestamp:
          payload[key] = entry.createdAt.toIso8601String();
          break;
        case ApiFieldType.scanType:
          payload[key] = entry.scanType;
          break;
        case ApiFieldType.note:
          payload[key] = entry.note;
          break;
        case ApiFieldType.staticValue:
          payload[key] = _expandTemplate(field.value, entry, gen);
          break;
      }
    }

    return payload.isEmpty ? entry.toApiPayload() : payload;
  }

  String _expandTemplate(
    String template,
    ScanEntry entry,
    String Function(String prefix) gen,
  ) {
    var out = template
        .replaceAll('{{value}}', entry.text)
        .replaceAll('{{scan}}', entry.text)
        .replaceAll('{{scan_type}}', entry.scanType)
        .replaceAll('{{note}}', entry.note)
        .replaceAll('{{timestamp}}', entry.createdAt.toIso8601String());
    if (out.contains('{{random_id}}')) {
      out = out.replaceAll('{{random_id}}', gen(''));
    }
    return out;
  }

  Uri buildGetUri(String baseUrl, Map<String, dynamic> payload) {
    final parsed = Uri.parse(baseUrl.trim());
    final merged = Map<String, String>.from(parsed.queryParameters);
    payload.forEach((key, value) {
      merged[key] = value?.toString() ?? '';
    });
    return parsed.replace(queryParameters: merged);
  }

  Future<ApiSendResult> sendEntry(
    ScanEntry entry, {
    ApiConfig? overrideConfig,
  }) async {
    final config = overrideConfig ?? await loadActiveConfig();
    if (config == null) {
      return const ApiSendResult(
        success: false,
        statusCode: 0,
        message: 'Belum ada API yang aktif. Pilih 1 API di Pengaturan REST API.',
        responseBody: '',
      );
    }
    final payload = buildPayload(entry, config);
    return sendPayload(payload, config);
  }

  Future<ApiSendResult> sendPayload(
    Map<String, dynamic> payload,
    ApiConfig config,
  ) async {
    if (!config.isConfigured) {
      return const ApiSendResult(
        success: false,
        statusCode: 0,
        message:
            'URL REST API belum valid (harus diawali http:// atau https://).',
        responseBody: '',
      );
    }

    final headers = <String, String>{
      'Accept': 'application/json, text/plain, */*',
    };
    if (config.headerKey.trim().isNotEmpty &&
        config.headerValue.trim().isNotEmpty) {
      headers[config.headerKey.trim()] = config.headerValue.trim();
    }

    try {
      late http.Response res;
      if (config.method.toUpperCase() == 'GET') {
        final uri = buildGetUri(config.endpointUrl, payload);
        res = await http.get(uri, headers: headers).timeout(
              const Duration(seconds: 15),
            );
      } else {
        headers['Content-Type'] = 'application/json';
        final uri = Uri.parse(config.endpointUrl.trim());
        res = await http
            .post(
              uri,
              headers: headers,
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 15));
      }

      final ok = res.statusCode >= 200 && res.statusCode < 300;
      final preview = res.body.length > 300
          ? '${res.body.substring(0, 300)}...'
          : res.body;

      return ApiSendResult(
        success: ok,
        statusCode: res.statusCode,
        message: ok
            ? 'Berhasil dikirim (${config.method} ${res.statusCode})'
            : 'Server merespons error HTTP ${res.statusCode}',
        responseBody: preview,
      );
    } catch (e) {
      return ApiSendResult(
        success: false,
        statusCode: 0,
        message: 'Gagal terhubung ke API: $e',
        responseBody: '',
      );
    }
  }
}
