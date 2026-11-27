enum ApiHttpMethod {
  post,
  get,
}

extension ApiHttpMethodExt on ApiHttpMethod {
  String get label => this == ApiHttpMethod.post ? 'POST' : 'GET';
}

class ApiConfig {
  final bool enabled;
  final bool autoSend;
  final String url;
  final ApiHttpMethod method;
  final String headerKey;
  final String headerValue;
  final String textParamName;

  const ApiConfig({
    this.enabled = false,
    this.autoSend = false,
    this.url = '',
    this.method = ApiHttpMethod.post,
    this.headerKey = 'Authorization',
    this.headerValue = '',
    this.textParamName = 'text',
  });

  bool get isReady => enabled && url.trim().isNotEmpty;

  ApiConfig copyWith({
    bool? enabled,
    bool? autoSend,
    String? url,
    ApiHttpMethod? method,
    String? headerKey,
    String? headerValue,
    String? textParamName,
  }) {
    return ApiConfig(
      enabled: enabled ?? this.enabled,
      autoSend: autoSend ?? this.autoSend,
      url: url ?? this.url,
      method: method ?? this.method,
      headerKey: headerKey ?? this.headerKey,
      headerValue: headerValue ?? this.headerValue,
      textParamName: textParamName ?? this.textParamName,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'autoSend': autoSend,
        'url': url,
        'method': method.name,
        'headerKey': headerKey,
        'headerValue': headerValue,
        'textParamName': textParamName,
      };

  factory ApiConfig.fromJson(Map<String, dynamic> map) {
    final mName = (map['method'] as String?) ?? 'post';
    final method = mName == 'get' ? ApiHttpMethod.get : ApiHttpMethod.post;
    return ApiConfig(
      enabled: (map['enabled'] as bool?) ?? false,
      autoSend: (map['autoSend'] as bool?) ?? false,
      url: (map['url'] as String?) ?? '',
      method: method,
      headerKey: (map['headerKey'] as String?) ?? 'Authorization',
      headerValue: (map['headerValue'] as String?) ?? '',
      textParamName: (map['textParamName'] as String?) ?? 'text',
    );
  }
}
