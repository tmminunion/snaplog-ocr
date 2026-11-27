import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/scan_entry.dart';
import '../services/api_service.dart';
import '../services/log_repository.dart';
import 'api_settings_screen.dart';
import 'camera_scan_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LogRepository _repo = LogRepository();
  final ApiService _apiService = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();

  ApiConfig _apiConfig = const ApiConfig();
  String _selectedCategory = 'Semua';
  String _searchQuery = '';
  bool _isBatchSyncing = false;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onRepoChanged);
    _repo.load();
    _loadApiConfig();
  }

  Future<void> _loadApiConfig() async {
    final cfg = await _apiService.loadConfig();
    if (mounted) setState(() => _apiConfig = cfg);
  }

  void _onRepoChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    _repo.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ScanEntry> get _filteredEntries {
    return _repo.entries.where((e) {
      final catMatch =
          _selectedCategory == 'Semua' || e.category == _selectedCategory;
      final q = _searchQuery.toLowerCase();
      final textMatch = q.isEmpty ||
          e.text.toLowerCase().contains(q) ||
          e.note.toLowerCase().contains(q) ||
          e.category.toLowerCase().contains(q) ||
          e.scanType.toLowerCase().contains(q);
      return catMatch && textMatch;
    }).toList();
  }

  Future<void> _openApiSettings() async {
    final updated = await Navigator.of(context).push<ApiConfig>(
      MaterialPageRoute(builder: (_) => const ApiSettingsScreen()),
    );
    if (updated != null && mounted) {
      setState(() => _apiConfig = updated);
    } else {
      await _loadApiConfig();
    }
  }

  Future<void> _openScanner({ScannerMode mode = ScannerMode.ocr}) async {
    final entry = await Navigator.of(context).push<ScanEntry>(
      MaterialPageRoute(builder: (_) => CameraScanScreen(initialMode: mode)),
    );
    if (entry == null) return;

    await _repo.addEntry(entry);

    if (_apiConfig.isConfigured && _apiConfig.autoSend) {
      await _sendSingleEntry(entry, silentIfMissing: true);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tersimpan: ${entry.text}'),
          backgroundColor: const Color(0xFF0F766E),
        ),
      );
    }
  }

  Future<bool> _sendSingleEntry(
    ScanEntry entry, {
    bool silentIfMissing = false,
  }) async {
    if (!_apiConfig.isConfigured) {
      if (!silentIfMissing && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Atur URL REST API dulu di ikon Cloud Settings.'),
            action: SnackBarAction(
              label: 'Atur',
              onPressed: _openApiSettings,
            ),
          ),
        );
      }
      return false;
    }

    final res = await _apiService.sendEntry(entry, overrideConfig: _apiConfig);
    await _repo.updateEntry(
      entry.copyWith(
        apiSynced: res.success,
        apiStatusCode: res.statusCode,
        apiLastResponse:
            res.responseBody.isNotEmpty ? res.responseBody : res.message,
      ),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${res.message} — ${entry.text}'),
          backgroundColor:
              res.success ? const Color(0xFF0F766E) : const Color(0xFFB91C1C),
        ),
      );
    }
    return res.success;
  }

  Future<void> _syncAllPending() async {
    if (_isBatchSyncing) return;
    if (!_apiConfig.isConfigured) {
      await _openApiSettings();
      return;
    }

    final pending = _repo.entries.where((e) => !e.apiSynced).toList();
    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Semua data sudah terkirim ke REST API.')),
      );
      return;
    }

    setState(() => _isBatchSyncing = true);
    int okCount = 0;
    for (final entry in pending) {
      final res =
          await _apiService.sendEntry(entry, overrideConfig: _apiConfig);
      if (res.success) okCount += 1;
      await _repo.updateEntry(
        entry.copyWith(
          apiSynced: res.success,
          apiStatusCode: res.statusCode,
          apiLastResponse:
              res.responseBody.isNotEmpty ? res.responseBody : res.message,
        ),
      );
    }
    if (mounted) {
      setState(() => _isBatchSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sync API (${_apiConfig.method}): $okCount/${pending.length} berhasil dikirim.',
          ),
          backgroundColor:
              okCount > 0 ? const Color(0xFF0F766E) : const Color(0xFFB91C1C),
        ),
      );
    }
  }

  Future<void> _exportCsv() async {
    final items = _filteredEntries;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada data log untuk diekspor.')),
      );
      return;
    }
    try {
      await _repo.shareCsv(subset: items);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal ekspor CSV: $e')),
        );
      }
    }
  }

  void _showEntryDetail(ScanEntry entry) {
    final textCtrl = TextEditingController(text: entry.text);
    final noteCtrl = TextEditingController(text: entry.note);
    String cat = entry.category;
    bool sending = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF11182C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            16,
            18,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      formatTimestamp(entry.createdAt),
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _typeChip(entry),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Salin teks',
                      icon: const Icon(
                        Icons.copy_rounded,
                        color: Color(0xFF00E5FF),
                        size: 20,
                      ),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: entry.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Teks disalin ke clipboard'),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      tooltip: 'Hapus',
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Color(0xFFFF5252),
                        size: 22,
                      ),
                      onPressed: () async {
                        await _repo.deleteEntry(entry.id);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      },
                    ),
                  ],
                ),
                if (entry.imagePath != null &&
                    File(entry.imagePath!).existsSync())
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        height: 165,
                        width: double.infinity,
                        color: const Color(0xFF050914),
                        child: InteractiveViewer(
                          child: Image.file(
                            File(entry.imagePath!),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                TextField(
                  controller: textCtrl,
                  maxLines: 3,
                  minLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Hasil Scan',
                    filled: true,
                    fillColor: const Color(0xFF0A0F1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Catatan',
                    filled: true,
                    fillColor: const Color(0xFF0A0F1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  children: kDefaultCategories.map((c) {
                    final sel = c == cat;
                    return ChoiceChip(
                      label: Text(c),
                      selected: sel,
                      onSelected: (_) => setModalState(() => cat = c),
                      selectedColor: const Color(0xFF00E5FF),
                      backgroundColor: const Color(0xFF1E293B),
                      labelStyle: TextStyle(
                        color: sel
                            ? const Color(0xFF0A0F1E)
                            : const Color(0xFFCBD5E1),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    );
                  }).toList(),
                ),
                if (entry.apiLastResponse != null &&
                    entry.apiLastResponse!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0F1E),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: (entry.apiSynced
                                ? const Color(0xFF00E676)
                                : const Color(0xFFFF5252))
                            .withAlpha(90),
                      ),
                    ),
                    child: Text(
                      'API (${entry.apiStatusCode ?? 0}): ${entry.apiLastResponse}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: sending
                            ? null
                            : () async {
                                setModalState(() => sending = true);
                                final updated = entry.copyWith(
                                  text: textCtrl.text.trim(),
                                  note: noteCtrl.text.trim(),
                                  category: cat,
                                );
                                await _repo.updateEntry(updated);
                                await _sendSingleEntry(updated);
                                if (ctx.mounted) {
                                  Navigator.of(ctx).pop();
                                }
                              },
                        icon: sending
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.cloud_upload_rounded, size: 18),
                        label: Text(
                          'Kirim ${_apiConfig.method}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF00E676),
                          side: const BorderSide(color: Color(0xFF00E676)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          final updated = entry.copyWith(
                            text: textCtrl.text.trim(),
                            note: noteCtrl.text.trim(),
                            category: cat,
                          );
                          await _repo.updateEntry(updated);
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: const Color(0xFF0A0F1E),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Simpan',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmClearAll() {
    if (_repo.entries.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF11182C),
        title: const Text(
          'Hapus Semua Log?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Seluruh data hasil scan dan foto bukti lokal akan dihapus permanen.',
          style: TextStyle(color: Color(0xFFCBD5E1)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF5252),
            ),
            onPressed: () async {
              await _repo.clearAll();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Hapus Semua'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredEntries;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1529),
        elevation: 0,
        title: const Row(
          children: [
            Icon(
              Icons.document_scanner_rounded,
              color: Color(0xFF00E5FF),
              size: 22,
            ),
            SizedBox(width: 8),
            Text(
              'SNAPLOG OCR',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Kirim Pending ke REST API',
            onPressed: _isBatchSyncing ? null : _syncAllPending,
            icon: _isBatchSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF00E5FF),
                    ),
                  )
                : Icon(
                    Icons.cloud_upload_rounded,
                    color: _apiConfig.isConfigured
                        ? const Color(0xFF00E5FF)
                        : const Color(0xFF64748B),
                  ),
          ),
          IconButton(
            tooltip: 'Pengaturan REST API (POST/GET)',
            onPressed: _openApiSettings,
            icon: const Icon(
              Icons.settings_ethernet_rounded,
              color: Color(0xFFFFB300),
            ),
          ),
          IconButton(
            tooltip: 'Ekspor CSV (Excel)',
            onPressed: _exportCsv,
            icon: const Icon(
              Icons.file_download_rounded,
              color: Color(0xFF00E676),
            ),
          ),
          IconButton(
            tooltip: 'Hapus Semua Log',
            onPressed: _confirmClearAll,
            icon: const Icon(
              Icons.delete_sweep_rounded,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'fab_qr',
            onPressed: () => _openScanner(mode: ScannerMode.qrBarcode),
            backgroundColor: const Color(0xFF00E676),
            foregroundColor: const Color(0xFF0A0F1E),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text(
              'QR/BAR',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.6),
            ),
          ),
          const SizedBox(width: 10),
          FloatingActionButton.extended(
            heroTag: 'fab_ocr',
            onPressed: () => _openScanner(mode: ScannerMode.ocr),
            backgroundColor: const Color(0xFF00E5FF),
            foregroundColor: const Color(0xFF0A0F1E),
            icon: const Icon(Icons.camera_alt_rounded),
            label: const Text(
              'SCAN OCR',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.6),
            ),
          ),
        ],
      ),
      body: !_repo.isLoaded
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
            )
          : Column(
              children: [
                _buildStatsBar(),
                _buildSearchAndFilter(),
                Expanded(
                  child: items.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, idx) => _buildLogTile(items[idx]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatsBar() {
    final apiStatus = _apiConfig.isConfigured
        ? '${_apiConfig.method}${_apiConfig.autoSend ? ' AUTO' : ''}'
        : 'OFFLINE';

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF132242), Color(0xFF0E172E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF00E5FF).withAlpha(75)),
      ),
      child: Row(
        children: [
          _statBox(
            label: 'TOTAL LOG',
            value: _repo.entries.length.toString(),
            color: const Color(0xFF00E5FF),
          ),
          const SizedBox(width: 10),
          _statBox(
            label: 'HARI INI',
            value: _repo.todayCount.toString(),
            color: const Color(0xFF00E676),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: _openApiSettings,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0F1E).withAlpha(170),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFFFB300).withAlpha(80),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'REST API',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      apiStatus,
                      style: const TextStyle(
                        color: Color(0xFFFFB300),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBox({
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0F1E).withAlpha(170),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(70)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilter() {
    final categories = ['Semua', ...kDefaultCategories];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _searchQuery = v),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Cari teks, QR/barcode, atau catatan...',
              hintStyle: const TextStyle(color: Color(0xFF64748B)),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: Color(0xFF64748B),
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFF94A3B8),
                        size: 18,
                      ),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFF11182C),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final cat = categories[i];
              final sel = cat == _selectedCategory;
              return GestureDetector(
                onTap: () => setState(() => _selectedCategory = cat),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: sel
                        ? const Color(0xFF00E5FF)
                        : const Color(0xFF131C33),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: sel
                          ? const Color(0xFF00E5FF)
                          : const Color(0xFF1E293B),
                    ),
                  ),
                  child: Text(
                    cat,
                    style: TextStyle(
                      color: sel
                          ? const Color(0xFF0A0F1E)
                          : const Color(0xFFCBD5E1),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _typeChip(ScanEntry entry) {
    final bool isQr = entry.scanType == 'qr';
    final bool isBar = entry.scanType == 'barcode';
    final color = isQr
        ? const Color(0xFF00E676)
        : isBar
            ? const Color(0xFFFFB300)
            : const Color(0xFF00E5FF);
    final label = isQr
        ? 'QR'
        : isBar
            ? 'BAR'
            : 'OCR';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildLogTile(ScanEntry entry) {
    final hasPhoto =
        entry.imagePath != null && File(entry.imagePath!).existsSync();

    return InkWell(
      onTap: () => _showEntryDetail(entry),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF11182C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1E293B)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 62,
                height: 62,
                color: const Color(0xFF050914),
                child: hasPhoto
                    ? Image.file(
                        File(entry.imagePath!),
                        fit: BoxFit.cover,
                      )
                    : Icon(
                        entry.scanType == 'ocr'
                            ? Icons.text_snippet_rounded
                            : Icons.qr_code_2_rounded,
                        color: const Color(0xFF475569),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _typeChip(entry),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          entry.category,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (entry.apiSynced)
                        const Icon(
                          Icons.cloud_done_rounded,
                          size: 14,
                          color: Color(0xFF00E676),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (entry.note.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Kirim ke REST API',
              onPressed: () => _sendSingleEntry(entry),
              icon: Icon(
                entry.apiSynced
                    ? Icons.check_circle_rounded
                    : Icons.send_rounded,
                color: entry.apiSynced
                    ? const Color(0xFF00E676)
                    : const Color(0xFF00E5FF),
                size: 19,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withAlpha(22),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF00E5FF).withAlpha(80),
                ),
              ),
              child: const Icon(
                Icons.qr_code_scanner_rounded,
                color: Color(0xFF00E5FF),
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Belum Ada Log Scan',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Gunakan tombol SCAN OCR untuk teks/angka atau QR/BAR untuk QR Code & Barcode. Data bisa diekspor ke CSV atau dikirim via REST API POST/GET.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
