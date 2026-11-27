export 'api_config.dart';

enum OcrFilterMode {
  all,
  numbersOnly,
  serialCode,
}

enum ScannerMode {
  ocr,
  qrBarcode,
}

extension OcrFilterModeExt on OcrFilterMode {
  String get label {
    switch (this) {
      case OcrFilterMode.all:
        return 'Semua Teks';
      case OcrFilterMode.numbersOnly:
        return 'Angka Saja';
      case OcrFilterMode.serialCode:
        return 'Kode / Serial';
    }
  }

  String get shortLabel {
    switch (this) {
      case OcrFilterMode.all:
        return 'Teks';
      case OcrFilterMode.numbersOnly:
        return 'Angka';
      case OcrFilterMode.serialCode:
        return 'Serial';
    }
  }
}

String applyOcrFilter(String raw, OcrFilterMode mode) {
  final cleaned = raw
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .join(' ')
      .trim();

  if (cleaned.isEmpty) return '';

  switch (mode) {
    case OcrFilterMode.all:
      return cleaned;
    case OcrFilterMode.numbersOnly:
      final matches = RegExp(r'\d+(?:[.,]\d+)?').allMatches(cleaned);
      return matches.map((m) => m.group(0)!).join(' ').trim();
    case OcrFilterMode.serialCode:
      final upper = cleaned.toUpperCase();
      final filtered = upper.replaceAll(RegExp(r'[^A-Z0-9\-_/. ]'), '');
      return filtered.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class ScanEntry {
  final String id;
  final String text;
  final String rawText;
  final String note;
  final String filterMode;
  final String scanType; // 'ocr', 'qr', 'barcode'
  final String? barcodeFormat;
  final String? imagePath;
  final DateTime createdAt;
  final bool apiSynced;
  final int? apiStatusCode;
  final String? apiLastResponse;

  const ScanEntry({
    required this.id,
    required this.text,
    required this.rawText,
    required this.note,
    required this.filterMode,
    this.scanType = 'ocr',
    this.barcodeFormat,
    required this.imagePath,
    required this.createdAt,
    this.apiSynced = false,
    this.apiStatusCode,
    this.apiLastResponse,
  });

  ScanEntry copyWith({
    String? text,
    String? note,
    bool? apiSynced,
    int? apiStatusCode,
    String? apiLastResponse,
  }) {
    return ScanEntry(
      id: id,
      text: text ?? this.text,
      rawText: rawText,
      note: note ?? this.note,
      filterMode: filterMode,
      scanType: scanType,
      barcodeFormat: barcodeFormat,
      imagePath: imagePath,
      createdAt: createdAt,
      apiSynced: apiSynced ?? this.apiSynced,
      apiStatusCode: apiStatusCode ?? this.apiStatusCode,
      apiLastResponse: apiLastResponse ?? this.apiLastResponse,
    );
  }

  Map<String, dynamic> toApiPayload() => {
        'id': id,
        'value': text,
        'raw_text': rawText,
        'scan_type': scanType,
        'barcode_format': barcodeFormat ?? '',
        'note': note,
        'filter_mode': filterMode,
        'timestamp': createdAt.toIso8601String(),
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'rawText': rawText,
        'note': note,
        'filterMode': filterMode,
        'scanType': scanType,
        'barcodeFormat': barcodeFormat,
        'imagePath': imagePath,
        'createdAt': createdAt.toIso8601String(),
        'apiSynced': apiSynced,
        'apiStatusCode': apiStatusCode,
        'apiLastResponse': apiLastResponse,
      };

  factory ScanEntry.fromJson(Map<String, dynamic> map) {
    return ScanEntry(
      id: (map['id'] as String?) ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      text: (map['text'] as String?) ?? '',
      rawText: (map['rawText'] as String?) ?? '',
      note: (map['note'] as String?) ?? '',
      filterMode: (map['filterMode'] as String?) ?? 'all',
      scanType: (map['scanType'] as String?) ?? 'ocr',
      barcodeFormat: map['barcodeFormat'] as String?,
      imagePath: map['imagePath'] as String?,
      createdAt: DateTime.tryParse((map['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      apiSynced: (map['apiSynced'] as bool?) ?? false,
      apiStatusCode: (map['apiStatusCode'] as num?)?.toInt(),
      apiLastResponse: map['apiLastResponse'] as String?,
    );
  }
}

String _csvEscape(String value) {
  final escaped = value.replaceAll('"', '""');
  if (escaped.contains(',') ||
      escaped.contains('"') ||
      escaped.contains('\n') ||
      escaped.contains('\r')) {
    return '"$escaped"';
  }
  return escaped;
}

String formatTimestamp(DateTime dt) {
  String p2(int v) => v.toString().padLeft(2, '0');
  return '${dt.year}-${p2(dt.month)}-${p2(dt.day)} ${p2(dt.hour)}:${p2(dt.minute)}:${p2(dt.second)}';
}

String buildCsvContent(List<ScanEntry> entries) {
  final buf = StringBuffer();
  // UTF-8 BOM so Microsoft Excel detects UTF-8 automatically
  buf.write('\uFEFF');
  buf.writeln(
    'No,Timestamp,Tipe,Format,Hasil_Scan,Catatan,Status_API,File_Bukti',
  );
  for (int i = 0; i < entries.length; i++) {
    final e = entries[i];
    final fileName = e.imagePath != null ? e.imagePath!.split('/').last : '';
    final apiState =
        e.apiSynced ? 'SENT (${e.apiStatusCode ?? 200})' : 'LOCAL';
    final row = [
      (i + 1).toString(),
      _csvEscape(formatTimestamp(e.createdAt)),
      _csvEscape(e.scanType.toUpperCase()),
      _csvEscape(e.barcodeFormat ?? e.filterMode),
      _csvEscape(e.text),
      _csvEscape(e.note),
      _csvEscape(apiState),
      _csvEscape(fileName),
    ].join(',');
    buf.writeln(row);
  }
  return buf.toString();
}
