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
  static const String _configKey = 'snaplog_ocr_api_config_v1';

  Future<ApiConfig> loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_configKey);
      if (raw != null && raw.isNotEmpty) {
        return ApiConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    return const ApiConfig();
  }

  Future<void> saveConfig(ApiConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(config.toJson()));
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
    final config = overrideConfig ?? await loadConfig();
    return sendPayload(entry.toApiPayload(), config);
  }

  Future<ApiSendResult> sendPayload(
    Map<String, dynamic> payload,
    ApiConfig config,
  ) async {
    if (!config.isConfigured) {
      return const ApiSendResult(
        success: false,
        statusCode: 0,
        message: 'URL REST API belum diatur (harus diawali http:// atau https://).',
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
