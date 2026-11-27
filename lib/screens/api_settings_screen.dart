import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/scan_entry.dart';
import '../services/api_service.dart';

class ApiSettingsScreen extends StatefulWidget {
  const ApiSettingsScreen({super.key});

  @override
  State<ApiSettingsScreen> createState() => _ApiSettingsScreenState();
}

class _ApiSettingsScreenState extends State<ApiSettingsScreen> {
  final ApiService _apiService = ApiService();
  ApiStore _store = const ApiStore();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = await _apiService.loadStore();
    if (!mounted) return;
    setState(() {
      _store = store;
      _loading = false;
    });
  }

  Future<void> _selectActive(String id) async {
    final nextId = _store.activeId == id ? null : id;
    final updated = await _apiService.setActiveProfile(nextId);
    if (!mounted) return;
    setState(() => _store = updated);
    final active = updated.activeProfile;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          active != null
              ? 'API aktif: ${active.name} (${active.method})'
              : 'Semua API dinonaktifkan (Mode Offline)',
        ),
        duration: const Duration(milliseconds: 1400),
        backgroundColor:
            active != null ? const Color(0xFF0F766E) : const Color(0xFF334155),
      ),
    );
  }

  Future<void> _openEditor({ApiConfig? existing}) async {
    final saved = await Navigator.of(context).push<ApiConfig>(
      MaterialPageRoute(
        builder: (_) => ApiEditorScreen(initialConfig: existing),
      ),
    );
    if (saved == null) return;
    final updated = await _apiService.upsertProfile(
      saved,
      setActive: existing == null && _store.activeId == null,
    );
    if (!mounted) return;
    setState(() => _store = updated);
  }

  Future<void> _confirmDelete(ApiConfig profile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF11182C),
        title: const Text(
          'Hapus API?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Konfigurasi "${profile.name}" akan dihapus permanen.',
          style: const TextStyle(color: Color(0xFFCBD5E1)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF5252),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final updated = await _apiService.deleteProfile(profile.id);
    if (!mounted) return;
    setState(() => _store = updated);
  }

  @override
  Widget build(BuildContext context) {
    final active = _store.activeProfile;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0F1E),
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'DAFTAR REST API',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
          ),
        ),
        actions: [
          if (active != null)
            TextButton(
              onPressed: () => _selectActive(active.id),
              child: const Text(
                'Nonaktifkan',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: const Color(0xFF00E5FF),
        foregroundColor: const Color(0xFF0A0F1E),
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'TAMBAH API',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
            )
          : _store.profiles.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 96),
                  itemCount: _store.profiles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _buildProfileCard(_store.profiles[i]),
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
                Icons.api_rounded,
                color: Color(0xFF00E5FF),
                size: 32,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Belum Ada Endpoint API',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tambahkan banyak konfigurasi REST API (POST/GET + custom field dinamis), lalu pilih 1 API yang aktif.',
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

  Widget _buildProfileCard(ApiConfig profile) {
    final isActive = _store.activeId == profile.id;
    final methodColor = profile.method == 'POST'
        ? const Color(0xFF00E5FF)
        : const Color(0xFF00E676);
    final fieldKeys = profile.customFields
        .map((f) => f.key.trim())
        .where((k) => k.isNotEmpty)
        .toList();

    return InkWell(
      onTap: () => _selectActive(profile.id),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF11182C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? const Color(0xFF00E676)
                : const Color(0xFF1E293B),
            width: isActive ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isActive
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: isActive
                      ? const Color(0xFF00E676)
                      : const Color(0xFF64748B),
                  size: 21,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: methodColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    profile.method,
                    style: TextStyle(
                      color: methodColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (profile.autoSend) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB300).withAlpha(30),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'AUTO',
                      style: TextStyle(
                        color: Color(0xFFFFB300),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              profile.endpointUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    fieldKeys.isEmpty
                        ? 'Default payload'
                        : '${fieldKeys.length} field: ${fieldKeys.join(', ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11.5,
                    ),
                  ),
                ),
                if (isActive)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withAlpha(28),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'AKTIF',
                      style: TextStyle(
                        color: Color(0xFF00E676),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: 'Edit API',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _openEditor(existing: profile),
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: Color(0xFF00E5FF),
                    size: 19,
                  ),
                ),
                IconButton(
                  tooltip: 'Hapus API',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _confirmDelete(profile),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFFF5252),
                    size: 19,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldRowData {
  final TextEditingController keyCtrl;
  final TextEditingController valCtrl;
  ApiFieldType type;

  _FieldRowData({
    required String key,
    required ApiFieldType type,
    required String value,
  })  : keyCtrl = TextEditingController(text: key),
        valCtrl = TextEditingController(text: value),
        type = type;

  ApiCustomField toField() => ApiCustomField(
        key: keyCtrl.text.trim(),
        type: type,
        value: valCtrl.text,
      );

  void dispose() {
    keyCtrl.dispose();
    valCtrl.dispose();
  }
}

class ApiEditorScreen extends StatefulWidget {
  final ApiConfig? initialConfig;

  const ApiEditorScreen({super.key, this.initialConfig});

  @override
  State<ApiEditorScreen> createState() => _ApiEditorScreenState();
}

class _ApiEditorScreenState extends State<ApiEditorScreen> {
  final ApiService _apiService = ApiService();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _headerKeyCtrl;
  late final TextEditingController _headerValCtrl;

  late String _id;
  late String _method;
  late bool _autoSend;
  final List<_FieldRowData> _fieldRows = [];

  bool _testing = false;
  ApiSendResult? _lastTestResult;
  String _previewSampleId = generateRandomIdString(length: 8);

  @override
  void initState() {
    super.initState();
    final cfg = widget.initialConfig;
    _id = cfg?.id ?? generateRandomIdString(length: 8, prefix: 'api_');
    _nameCtrl = TextEditingController(text: cfg?.name ?? '');
    _urlCtrl = TextEditingController(text: cfg?.endpointUrl ?? '');
    _headerKeyCtrl = TextEditingController(text: cfg?.headerKey ?? '');
    _headerValCtrl = TextEditingController(text: cfg?.headerValue ?? '');
    _method = cfg?.method ?? 'POST';
    _autoSend = cfg?.autoSend ?? false;

    final initialFields =
        (cfg != null && cfg.customFields.isNotEmpty)
            ? cfg.customFields
            : defaultApiFields();
    for (final f in initialFields) {
      _fieldRows.add(
        _FieldRowData(key: f.key, type: f.type, value: f.value),
      );
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _headerKeyCtrl.dispose();
    _headerValCtrl.dispose();
    for (final row in _fieldRows) {
      row.dispose();
    }
    super.dispose();
  }

  ApiConfig _buildConfig() {
    final fields = _fieldRows
        .map((r) => r.toField())
        .where((f) => f.key.isNotEmpty)
        .toList();
    final cleanName = _nameCtrl.text.trim();
    return ApiConfig(
      id: _id,
      name: cleanName.isEmpty ? 'API Endpoint' : cleanName,
      endpointUrl: _urlCtrl.text.trim(),
      method: _method,
      headerKey: _headerKeyCtrl.text.trim(),
      headerValue: _headerValCtrl.text.trim(),
      autoSend: _autoSend,
      customFields: fields,
    );
  }

  void _addFieldRow({
    String key = '',
    ApiFieldType type = ApiFieldType.staticValue,
    String value = '',
  }) {
    setState(() {
      _fieldRows.add(_FieldRowData(key: key, type: type, value: value));
    });
  }

  void _removeFieldRow(int index) {
    setState(() {
      final removed = _fieldRows.removeAt(index);
      removed.dispose();
    });
  }

  void _save() {
    final cfg = _buildConfig();
    if (!cfg.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL API harus diawali http:// atau https://'),
          backgroundColor: Color(0xFFB91C1C),
        ),
      );
      return;
    }
    Navigator.of(context).pop(cfg);
  }

  Map<String, dynamic> _buildPreviewPayload() {
    final cfg = _buildConfig();
    final sampleEntry = ScanEntry(
      id: 'sample_1',
      text: 'SCAN2API-001',
      rawText: 'SCAN2API-001',
      note: 'Contoh catatan',
      filterMode: 'all',
      scanType: 'qr',
      barcodeFormat: 'QR_CODE',
      imagePath: null,
      createdAt: DateTime.now(),
    );
    return _apiService.buildPayload(
      sampleEntry,
      cfg,
      randomGenerator: (prefix) => '$prefix$_previewSampleId',
    );
  }

  Future<void> _testConnection() async {
    final cfg = _buildConfig();
    setState(() {
      _testing = true;
      _lastTestResult = null;
    });

    final sampleEntry = ScanEntry(
      id: 'test_${DateTime.now().millisecondsSinceEpoch}',
      text: 'SCAN2API-TEST-001',
      rawText: 'SCAN2API-TEST-001',
      note: 'Test koneksi Scan2API',
      filterMode: 'all',
      scanType: 'qr',
      barcodeFormat: 'QR_CODE',
      imagePath: null,
      createdAt: DateTime.now(),
    );

    final payload = _apiService.buildPayload(sampleEntry, cfg);
    final res = await _apiService.sendPayload(payload, cfg);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _lastTestResult = res;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialConfig != null;
    final previewMap = _buildPreviewPayload();
    final previewText = _method == 'POST'
        ? const JsonEncoder.withIndent('  ').convert(previewMap)
        : Uri(
            queryParameters: previewMap.map(
              (k, v) => MapEntry(k, v?.toString() ?? ''),
            ),
          ).query;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0F1E),
        surfaceTintColor: Colors.transparent,
        title: Text(
          isEdit ? 'EDIT REST API' : 'TAMBAH REST API',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded, color: Color(0xFF00E676)),
            label: const Text(
              'Simpan',
              style: TextStyle(
                color: Color(0xFF00E676),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 36),
        children: [
          _sectionLabel('NAMA API'),
          const SizedBox(height: 6),
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: _inputDeco(
              hint: 'Misal: Webhook Gudang / Server Produksi',
              icon: Icons.label_outline_rounded,
            ),
          ),
          const SizedBox(height: 14),

          _sectionLabel('ENDPOINT URL'),
          const SizedBox(height: 6),
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: _inputDeco(
              hint: 'https://example.com/api/scan',
              icon: Icons.link_rounded,
            ),
          ),
          const SizedBox(height: 16),

          _sectionLabel('HTTP METHOD'),
          const SizedBox(height: 6),
          Row(
            children: ['POST', 'GET'].map((m) {
              final selected = _method == m;
              final color = m == 'POST'
                  ? const Color(0xFF00E5FF)
                  : const Color(0xFF00E676);
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: m == 'POST' ? 8 : 0),
                  child: GestureDetector(
                    onTap: () => setState(() => _method = m),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: selected
                            ? color.withAlpha(35)
                            : const Color(0xFF11182C),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? color : const Color(0xFF1E293B),
                          width: selected ? 1.6 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            m,
                            style: TextStyle(
                              color: selected
                                  ? color
                                  : const Color(0xFF94A3B8),
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            m == 'POST' ? 'JSON Body' : 'Query String',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          _sectionLabel('CUSTOM HEADER (OPSIONAL)'),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _headerKeyCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: _inputDeco(hint: 'Authorization'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _headerValCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: _inputDeco(hint: 'Bearer token / API key'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF11182C),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: SwitchListTile(
              value: _autoSend,
              activeThumbColor: const Color(0xFF00E5FF),
              title: const Text(
                'Auto-Send Saat Scan',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: const Text(
                'Kirim otomatis setiap hasil scan tersimpan',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
              ),
              onChanged: (v) => setState(() => _autoSend = v),
            ),
          ),
          const SizedBox(height: 20),

          // Dynamic Custom Fields Header + Add (+) Button
          Row(
            children: [
              Expanded(child: _sectionLabel('CUSTOM FIELDS / PAYLOAD')),
              FilledButton.icon(
                onPressed: () => _addFieldRow(),
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const Text(
                  'Tambah',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: const Color(0xFF0A0F1E),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_fieldRows.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF11182C),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: const Text(
                'Kosong — tekan tombol + Tambah untuk menyusun key & value custom (termasuk ID Generator string acak).',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            )
          else
            ...List.generate(_fieldRows.length, (i) => _buildFieldCard(i)),

          const SizedBox(height: 16),

          // Live Payload Preview
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1426),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _method == 'POST'
                          ? 'PREVIEW JSON BODY'
                          : 'PREVIEW QUERY PARAMS',
                      style: const TextStyle(
                        color: Color(0xFF00E5FF),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(
                        () => _previewSampleId =
                            generateRandomIdString(length: 8),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.autorenew_rounded,
                            size: 14,
                            color: Color(0xFF00E676),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Acak ID',
                            style: TextStyle(
                              color: Color(0xFF00E676),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _method == 'GET' ? '?$previewText' : previewText,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 11.5,
                    height: 1.4,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Test API Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _testing ? null : _testConnection,
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF00E5FF),
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(
                _testing
                    ? 'Mengirim Test $_method...'
                    : 'Test Kirim API ($_method)',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF00E5FF),
                side: const BorderSide(color: Color(0xFF00E5FF)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          if (_lastTestResult != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_lastTestResult!.success
                        ? const Color(0xFF00E676)
                        : const Color(0xFFFF5252))
                    .withAlpha(22),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (_lastTestResult!.success
                          ? const Color(0xFF00E676)
                          : const Color(0xFFFF5252))
                      .withAlpha(110),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _lastTestResult!.message,
                    style: TextStyle(
                      color: _lastTestResult!.success
                          ? const Color(0xFF00E676)
                          : const Color(0xFFFF5252),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  if (_lastTestResult!.responseBody.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      _lastTestResult!.responseBody,
                      style: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 11.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFieldCard(int index) {
    final row = _fieldRows[index];
    final showValueInput = row.type == ApiFieldType.staticValue ||
        row.type == ApiFieldType.randomString;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF11182C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 5,
                child: TextField(
                  controller: row.keyCtrl,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: _inputDeco(
                    hint: 'Key (mis. id, kode)',
                    dense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0F1E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ApiFieldType>(
                      value: row.type,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF11182C),
                      style: const TextStyle(
                        color: Color(0xFF00E5FF),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      items: ApiFieldType.values
                          .map(
                            (t) => DropdownMenuItem(
                              value: t,
                              child: Text(
                                t.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (next) {
                        if (next == null) return;
                        setState(() => row.type = next);
                      },
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Hapus field',
                visualDensity: VisualDensity.compact,
                onPressed: () => _removeFieldRow(index),
                icon: const Icon(
                  Icons.close_rounded,
                  color: Color(0xFFFF5252),
                  size: 18,
                ),
              ),
            ],
          ),
          if (showValueInput) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: row.valCtrl,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: _inputDeco(
                      hint: row.type == ApiFieldType.randomString
                          ? 'Prefix opsional (mis. SL- atau kosong)'
                          : 'Isi nilai custom (bisa pakai {{value}} / {{random_id}})',
                      dense: true,
                    ),
                  ),
                ),
                if (row.type == ApiFieldType.staticValue) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Generate String Acak',
                    onPressed: () {
                      row.valCtrl.text = generateRandomIdString(length: 10);
                      setState(() {});
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676).withAlpha(28),
                    ),
                    icon: const Icon(
                      Icons.auto_fix_high_rounded,
                      color: Color(0xFF00E676),
                      size: 18,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.0,
      ),
    );
  }

  InputDecoration _inputDeco({
    required String hint,
    IconData? icon,
    bool dense = false,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
      filled: true,
      fillColor: dense ? const Color(0xFF0A0F1E) : const Color(0xFF11182C),
      isDense: dense,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: dense ? 10 : 12,
      ),
      prefixIcon: icon != null
          ? Icon(icon, color: const Color(0xFF00E5FF), size: 19)
          : null,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(dense ? 10 : 12),
        borderSide: const BorderSide(color: Color(0xFF1E293B)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(dense ? 10 : 12),
        borderSide: const BorderSide(color: Color(0xFF1E293B)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(dense ? 10 : 12),
        borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 1.4),
      ),
    );
  }
}
