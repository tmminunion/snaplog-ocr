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
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _repo.entries;
    return _repo.entries.where((e) {
      return e.text.toLowerCase().contains(q) ||
          e.note.toLowerCase().contains(q) ||
          e.scanType.toLowerCase().contains(q);
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

  Future<void> _handleSavedScan(ScanEntry entry) async {
    await _repo.addEntry(entry);
    if (_apiConfig.isConfigured && _apiConfig.autoSend) {
      await _sendSingleEntry(entry, silentIfMissing: true, showToast: false);
    }
  }

  Future<void> _openScanner({ScannerMode mode = ScannerMode.ocr}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CameraScanScreen(
          initialMode: mode,
          onScanSaved: _handleSavedScan,
        ),
      ),
    );
  }

  Future<bool> _sendSingleEntry(
    ScanEntry entry, {
    bool silentIfMissing = false,
    bool showToast = true,
  }) async {
    if (!_apiConfig.isConfigured) {
      if (!silentIfMissing && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Atur URL REST API dulu di Pengaturan API.'),
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

    if (showToast && mounted) {
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
            'Sync API (${_apiConfig.method}): $okCount/${pending.length} berhasil.',
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
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Row(
                  children: [
                    _typeChip(entry),
                    const SizedBox(width: 8),
                    Text(
                      formatTimestamp(entry.createdAt),
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
                    padding: const EdgeInsets.only(top: 6, bottom: 12),
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
                    labelText: 'Catatan (opsional)',
                    filled: true,
                    fillColor: const Color(0xFF0A0F1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
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
        backgroundColor: const Color(0xFF0A0F1E),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Row(
          children: [
            Icon(
              Icons.document_scanner_rounded,
              color: Color(0xFF00E5FF),
              size: 21,
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
            tooltip: 'Sync Pending ke REST API',
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
                    Icons.cloud_upload_outlined,
                    color: _apiConfig.isConfigured
                        ? const Color(0xFF00E5FF)
                        : const Color(0xFF64748B),
                  ),
          ),
          IconButton(
            tooltip: 'Pengaturan REST API',
            onPressed: _openApiSettings,
            icon: const Icon(
              Icons.tune_rounded,
              color: Color(0xFFCBD5E1),
            ),
          ),
          PopupMenuButton<String>(
            color: const Color(0xFF11182C),
            icon: const Icon(Icons.more_vert_rounded, color: Color(0xFFCBD5E1)),
            onSelected: (val) {
              if (val == 'csv') _exportCsv();
              if (val == 'clear') _confirmClearAll();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'csv',
                child: Row(
                  children: [
                    Icon(
                      Icons.file_download_rounded,
                      color: Color(0xFF00E676),
                      size: 19,
                    ),
                    SizedBox(width: 10),
                    Text('Ekspor CSV (Excel)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFFF5252),
                      size: 19,
                    ),
                    SizedBox(width: 10),
                    Text('Hapus Semua Log'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'fab_qr',
            elevation: 2,
            onPressed: () => _openScanner(mode: ScannerMode.qrBarcode),
            backgroundColor: const Color(0xFF00E676),
            foregroundColor: const Color(0xFF0A0F1E),
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
            label: const Text(
              'QR / BAR',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
            ),
          ),
          const SizedBox(width: 10),
          FloatingActionButton.extended(
            heroTag: 'fab_ocr',
            elevation: 2,
            onPressed: () => _openScanner(mode: ScannerMode.ocr),
            backgroundColor: const Color(0xFF00E5FF),
            foregroundColor: const Color(0xFF0A0F1E),
            icon: const Icon(Icons.camera_alt_rounded, size: 20),
            label: const Text(
              'SCAN OCR',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
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
                _buildSummaryBar(),
                _buildSearchBar(),
                Expanded(
                  child: items.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
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

  Widget _buildSummaryBar() {
    final apiStatus = _apiConfig.isConfigured
        ? '${_apiConfig.method}${_apiConfig.autoSend ? ' • AUTO' : ''}'
        : 'OFFLINE';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        children: [
          _miniStat(
            'TOTAL',
            _repo.entries.length.toString(),
            const Color(0xFF00E5FF),
          ),
          const SizedBox(width: 8),
          _miniStat(
            'HARI INI',
            _repo.todayCount.toString(),
            const Color(0xFF00E676),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: _openApiSettings,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF11182C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _apiConfig.isConfigured
                        ? const Color(0xFFFFB300).withAlpha(110)
                        : const Color(0xFF1E293B),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'API',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      apiStatus,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFFB300),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
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

  Widget _miniStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF11182C),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E293B)),
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
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Cari hasil scan...',
          hintStyle: const TextStyle(color: Color(0xFF64748B)),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF64748B),
            size: 20,
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
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1E293B)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1E293B)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF00E5FF)),
          ),
        ),
      ),
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
        color: color.withAlpha(28),
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
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF11182C),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1E293B)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 56,
                height: 56,
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
                      const SizedBox(width: 8),
                      Text(
                        formatTimestamp(entry.createdAt).substring(5, 16),
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                        ),
                      ),
                      if (entry.apiSynced) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.cloud_done_rounded,
                          size: 14,
                          color: Color(0xFF00E676),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
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
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withAlpha(20),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF00E5FF).withAlpha(75),
                ),
              ),
              child: const Icon(
                Icons.qr_code_scanner_rounded,
                color: Color(0xFF00E5FF),
                size: 32,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Belum Ada Log Scan',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap SCAN OCR atau QR / BAR di bawah untuk mulai memindai otomatis.',
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
