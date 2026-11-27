import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/scan_entry.dart';
import '../services/log_repository.dart';
import 'camera_scan_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LogRepository _repo = LogRepository();
  final TextEditingController _searchCtrl = TextEditingController();

  String _selectedCategory = 'Semua';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onRepoChanged);
    _repo.load();
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
          e.category.toLowerCase().contains(q);
      return catMatch && textMatch;
    }).toList();
  }

  Future<void> _openScanner() async {
    final entry = await Navigator.of(context).push<ScanEntry>(
      MaterialPageRoute(builder: (_) => const CameraScanScreen()),
    );
    if (entry != null) {
      await _repo.addEntry(entry);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tersimpan: ${entry.text}'),
            backgroundColor: const Color(0xFF0F766E),
          ),
        );
      }
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
                          const SnackBar(content: Text('Teks disalin ke clipboard')),
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
                if (entry.imagePath != null && File(entry.imagePath!).existsSync())
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        height: 170,
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
                    labelText: 'Hasil OCR',
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
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
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
                      'Simpan Perubahan',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openScanner,
        backgroundColor: const Color(0xFF00E5FF),
        foregroundColor: const Color(0xFF0A0F1E),
        icon: const Icon(Icons.camera_alt_rounded),
        label: const Text(
          'SCAN OCR',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
        ),
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
          _statBox(
            label: 'ENGINE',
            value: 'OFFLINE',
            color: const Color(0xFFFFB300),
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
              hintText: 'Cari angka, serial, atau catatan...',
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
                width: 64,
                height: 64,
                color: const Color(0xFF050914),
                child: hasPhoto
                    ? Image.file(
                        File(entry.imagePath!),
                        fit: BoxFit.cover,
                      )
                    : const Icon(
                        Icons.text_snippet_rounded,
                        color: Color(0xFF475569),
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withAlpha(28),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          entry.category,
                          style: const TextStyle(
                            color: Color(0xFF00E5FF),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatTimestamp(entry.createdAt).substring(5, 16),
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                        ),
                      ),
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
              tooltip: 'Salin',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: entry.text));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Disalin: ${entry.text}')),
                );
              },
              icon: const Icon(
                Icons.copy_rounded,
                color: Color(0xFF64748B),
                size: 18,
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
                Icons.document_scanner_rounded,
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
              'Tekan tombol SCAN OCR di bawah untuk membidik angka meteran, nomor seri, atau label secara offline.',
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
