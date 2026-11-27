import 'dart:math';

const String _kRandomChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
final Random _kSecureRandom = Random.secure();

/// Generates a readable uppercase alphanumeric random ID string.
String generateRandomIdString({int length = 10, String prefix = ''}) {
  final buf = StringBuffer(prefix);
  for (int i = 0; i < length; i++) {
    buf.write(_kRandomChars[_kSecureRandom.nextInt(_kRandomChars.length)]);
  }
  return buf.toString();
}

enum ApiFieldType {
  scanValue,
  randomString,
  staticValue,
  timestamp,
  scanType,
  note,
}

extension ApiFieldTypeExt on ApiFieldType {
  String get label {
    switch (this) {
      case ApiFieldType.scanValue:
        return 'Hasil Scan';
      case ApiFieldType.randomString:
        return 'ID Generator (Acak)';
      case ApiFieldType.staticValue:
        return 'Custom Value';
      case ApiFieldType.timestamp:
        return 'Timestamp';
      case ApiFieldType.scanType:
        return 'Tipe Scan';
      case ApiFieldType.note:
        return 'Catatan';
    }
  }

  String get shortTag {
    switch (this) {
      case ApiFieldType.scanValue:
        return 'SCAN';
      case ApiFieldType.randomString:
        return 'GEN ID';
      case ApiFieldType.staticValue:
        return 'CUSTOM';
      case ApiFieldType.timestamp:
        return 'TIME';
      case ApiFieldType.scanType:
        return 'TYPE';
      case ApiFieldType.note:
        return 'NOTE';
    }
  }
}

class ApiCustomField {
  final String key;
  final ApiFieldType type;
  final String value; // Static value or optional prefix for randomString

  const ApiCustomField({
    required this.key,
    required this.type,
    this.value = '',
  });

  ApiCustomField copyWith({
    String? key,
    ApiFieldType? type,
    String? value,
  }) {
    return ApiCustomField(
      key: key ?? this.key,
      type: type ?? this.type,
      value: value ?? this.value,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'type': type.name,
        'value': value,
      };

  factory ApiCustomField.fromJson(Map<String, dynamic> map) {
    final typeName = (map['type'] as String?) ?? ApiFieldType.staticValue.name;
    final parsedType = ApiFieldType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => ApiFieldType.staticValue,
    );
    return ApiCustomField(
      key: (map['key'] as String?) ?? '',
      type: parsedType,
      value: (map['value'] as String?) ?? '',
    );
  }
}

List<ApiCustomField> defaultApiFields() => const [
      ApiCustomField(key: 'id', type: ApiFieldType.randomString, value: 'SL-'),
      ApiCustomField(key: 'value', type: ApiFieldType.scanValue),
      ApiCustomField(key: 'scan_type', type: ApiFieldType.scanType),
      ApiCustomField(key: 'timestamp', type: ApiFieldType.timestamp),
    ];

class ApiConfig {
  final String id;
  final String name;
  final String endpointUrl;
  final String method; // 'POST' or 'GET'
  final String headerKey;
  final String headerValue;
  final bool autoSend;
  final List<ApiCustomField> customFields;

  const ApiConfig({
    this.id = '',
    this.name = 'API Utama',
    this.endpointUrl = '',
    this.method = 'POST',
    this.headerKey = '',
    this.headerValue = '',
    this.autoSend = false,
    this.customFields = const [],
  });

  bool get isConfigured =>
      endpointUrl.trim().startsWith('http://') ||
      endpointUrl.trim().startsWith('https://');

  ApiConfig copyWith({
    String? id,
    String? name,
    String? endpointUrl,
    String? method,
    String? headerKey,
    String? headerValue,
    bool? autoSend,
    List<ApiCustomField>? customFields,
  }) {
    return ApiConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      endpointUrl: endpointUrl ?? this.endpointUrl,
      method: method ?? this.method,
      headerKey: headerKey ?? this.headerKey,
      headerValue: headerValue ?? this.headerValue,
      autoSend: autoSend ?? this.autoSend,
      customFields: customFields ?? this.customFields,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'endpointUrl': endpointUrl,
        'method': method,
        'headerKey': headerKey,
        'headerValue': headerValue,
        'autoSend': autoSend,
        'customFields': customFields.map((f) => f.toJson()).toList(),
      };

  factory ApiConfig.fromJson(Map<String, dynamic> map) {
    final m = ((map['method'] as String?) ?? 'POST').toUpperCase();
    final rawFields = map['customFields'] as List<dynamic>?;
    final fields = rawFields != null
        ? rawFields
            .map((e) => ApiCustomField.fromJson(e as Map<String, dynamic>))
            .toList()
        : defaultApiFields();

    return ApiConfig(
      id: (map['id'] as String?) ??
          generateRandomIdString(length: 8, prefix: 'api_'),
      name: ((map['name'] as String?) ?? '').trim().isEmpty
          ? 'API Endpoint'
          : (map['name'] as String).trim(),
      endpointUrl: (map['endpointUrl'] as String?) ?? '',
      method: m == 'GET' ? 'GET' : 'POST',
      headerKey: (map['headerKey'] as String?) ?? '',
      headerValue: (map['headerValue'] as String?) ?? '',
      autoSend: (map['autoSend'] as bool?) ?? false,
      customFields: fields,
    );
  }
}

class ApiStore {
  final List<ApiConfig> profiles;
  final String? activeId;

  const ApiStore({
    this.profiles = const [],
    this.activeId,
  });

  ApiConfig? get activeProfile {
    if (activeId == null || activeId!.isEmpty) return null;
    for (final p in profiles) {
      if (p.id == activeId) return p;
    }
    return null;
  }

  ApiStore copyWith({
    List<ApiConfig>? profiles,
    String? activeId,
    bool clearActive = false,
  }) {
    return ApiStore(
      profiles: profiles ?? this.profiles,
      activeId: clearActive ? null : (activeId ?? this.activeId),
    );
  }

  Map<String, dynamic> toJson() => {
        'activeId': activeId,
        'profiles': profiles.map((p) => p.toJson()).toList(),
      };

  factory ApiStore.fromJson(Map<String, dynamic> map) {
    final rawList = (map['profiles'] as List<dynamic>?) ?? const [];
    final profiles = rawList
        .map((e) => ApiConfig.fromJson(e as Map<String, dynamic>))
        .toList();
    final activeId = map['activeId'] as String?;
    final validActive = profiles.any((p) => p.id == activeId) ? activeId : null;
    return ApiStore(profiles: profiles, activeId: validActive);
  }
}
