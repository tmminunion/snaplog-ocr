import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/scan_entry.dart';

class LogRepository extends ChangeNotifier {
  static const String _storageKey = 'snaplog_ocr_entries_v1';

  final List<ScanEntry> _entries = [];
  bool _loaded = false;

  List<ScanEntry> get entries => List.unmodifiable(_entries);
  List<ScanEntry> get unsyncedEntries =>
      _entries.where((e) => !e.apiSynced).toList(growable: false);
  bool get isLoaded => _loaded;

  int get todayCount {
    final now = DateTime.now();
    return _entries.where((e) {
      return e.createdAt.year == now.year &&
          e.createdAt.month == now.month &&
          e.createdAt.day == now.day;
    }).length;
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      _entries.clear();
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final item in list) {
          _entries.add(ScanEntry.fromJson(item as Map<String, dynamic>));
        }
      }
    } catch (_) {
      // Fallback to empty list on corrupted storage
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode(_entries.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, payload);
    } catch (_) {}
  }

  Future<void> addEntry(ScanEntry entry) async {
    _entries.insert(0, entry);
    notifyListeners();
    await _persist();
  }

  Future<void> updateEntry(ScanEntry updated) async {
    final idx = _entries.indexWhere((e) => e.id == updated.id);
    if (idx < 0) return;
    _entries[idx] = updated;
    notifyListeners();
    await _persist();
  }

  Future<void> deleteEntry(String id) async {
    final idx = _entries.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    final removed = _entries.removeAt(idx);
    if (removed.imagePath != null) {
      try {
        final file = File(removed.imagePath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
    notifyListeners();
    await _persist();
  }

  Future<void> clearAll() async {
    for (final e in _entries) {
      if (e.imagePath != null) {
        try {
          final f = File(e.imagePath!);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
    _entries.clear();
    notifyListeners();
    await _persist();
  }

  Future<String> exportCsvFile({List<ScanEntry>? subset}) async {
    final target = subset ?? _entries;
    final csv = buildCsvContent(target);
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    String p2(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${p2(now.month)}${p2(now.day)}_${p2(now.hour)}${p2(now.minute)}';
    final file = File('${dir.path}/Scan2API_$stamp.csv');
    await file.writeAsString(csv, flush: true);
    return file.path;
  }

  Future<void> shareCsv({List<ScanEntry>? subset}) async {
    final csvPath = await exportCsvFile(subset: subset);
    await Share.shareXFiles(
      [XFile(csvPath, mimeType: 'text/csv')],
      subject: 'Scan2API Export CSV',
      text: 'Rekap hasil scan Scan2API (${(subset ?? _entries).length} data).',
    );
  }

  Future<String> exportJsonFile({List<ScanEntry>? subset}) async {
    final target = subset ?? _entries;
    final jsonStr = const JsonEncoder.withIndent('  ')
        .convert(target.map((e) => e.toJson()).toList());
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    String p2(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${p2(now.month)}${p2(now.day)}_${p2(now.hour)}${p2(now.minute)}';
    final file = File('${dir.path}/Scan2API_$stamp.json');
    await file.writeAsString(jsonStr, flush: true);
    return file.path;
  }

  Future<void> shareJson({List<ScanEntry>? subset}) async {
    final jsonPath = await exportJsonFile(subset: subset);
    await Share.shareXFiles(
      [XFile(jsonPath, mimeType: 'application/json')],
      subject: 'Scan2API Export JSON',
      text: 'Rekap hasil scan JSON Scan2API (${(subset ?? _entries).length} data).',
    );
  }
}
