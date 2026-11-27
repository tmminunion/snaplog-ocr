enum OcrFilterMode {
  all,
  numbersOnly,
  serialCode,
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

const List<String> kDefaultCategories = [
  'Meteran',
  'Part / Serial',
  'Inspeksi',
  'Stok / Gudang',
  'Lainnya',
];

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
  final String category;
  final String note;
  final String filterMode;
  final String? imagePath;
  final DateTime createdAt;

  const ScanEntry({
    required this.id,
    required this.text,
    required this.rawText,
    required this.category,
    required this.note,
    required this.filterMode,
    required this.imagePath,
    required this.createdAt,
  });

  ScanEntry copyWith({
    String? text,
    String? category,
    String? note,
  }) {
    return ScanEntry(
      id: id,
      text: text ?? this.text,
      rawText: rawText,
      category: category ?? this.category,
      note: note ?? this.note,
      filterMode: filterMode,
      imagePath: imagePath,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'rawText': rawText,
        'category': category,
        'note': note,
        'filterMode': filterMode,
        'imagePath': imagePath,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ScanEntry.fromJson(Map<String, dynamic> map) {
    return ScanEntry(
      id: (map['id'] as String?) ?? DateTime.now().millisecondsSinceEpoch.toString(),
      text: (map['text'] as String?) ?? '',
      rawText: (map['rawText'] as String?) ?? '',
      category: (map['category'] as String?) ?? 'Lainnya',
      note: (map['note'] as String?) ?? '',
      filterMode: (map['filterMode'] as String?) ?? 'all',
      imagePath: map['imagePath'] as String?,
      createdAt: DateTime.tryParse((map['createdAt'] as String?) ?? '') ??
          DateTime.now(),
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
  buf.writeln('No,Timestamp,Kategori,Hasil_OCR,Catatan,Mode_Filter,File_Bukti');
  for (int i = 0; i < entries.length; i++) {
    final e = entries[i];
    final fileName =
        e.imagePath != null ? e.imagePath!.split('/').last : '';
    final row = [
      (i + 1).toString(),
      _csvEscape(formatTimestamp(e.createdAt)),
      _csvEscape(e.category),
      _csvEscape(e.text),
      _csvEscape(e.note),
      _csvEscape(e.filterMode),
      _csvEscape(fileName),
    ].join(',');
    buf.writeln(row);
  }
  return buf.toString();
}
