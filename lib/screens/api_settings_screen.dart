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
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _headerKeyCtrl = TextEditingController();
  final TextEditingController _headerValCtrl = TextEditingController();

  String _method = 'POST';
  bool _autoSend = false;
  bool _loading = true;
  bool _testing = false;
  ApiSendResult? _lastTestResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await _apiService.loadConfig();
    if (!mounted) return;
    _urlCtrl.text = cfg.endpointUrl;
    _headerKeyCtrl.text = cfg.headerKey;
    _headerValCtrl.text = cfg.headerValue;
    setState(() {
      _method = cfg.method;
      _autoSend = cfg.autoSend;
      _loading = false;
    });
  }

  ApiConfig _currentConfig() => ApiConfig(
        endpointUrl: _urlCtrl.text.trim(),
        method: _method,
        headerKey: _headerKeyCtrl.text.trim(),
        headerValue: _headerValCtrl.text.trim(),
        autoSend: _autoSend,
      );

  Future<void> _save() async {
    final cfg = _currentConfig();
    await _apiService.saveConfig(cfg);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Konfigurasi REST API tersimpan'),
        backgroundColor: Color(0xFF0F766E),
      ),
    );
    Navigator.of(context).pop(cfg);
  }

  Future<void> _testConnection() async {
    final cfg = _currentConfig();
    setState(() {
      _testing = true;
      _lastTestResult = null;
    });

    final samplePayload = {
      'id': 'test_${DateTime.now().millisecondsSinceEpoch}',
      'value': 'SNAPLOG-TEST-001',
      'scan_type': 'qr',
      'barcode_format': 'QR_CODE',
      'note': 'Test koneksi dari SnapLog OCR',
      'timestamp': DateTime.now().toIso8601String(),
    };

    final res = await _apiService.sendPayload(samplePayload, cfg);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _lastTestResult = res;
    });
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _headerKeyCtrl.dispose();
    _headerValCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0F1E),
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'PENGATURAN REST API',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_rounded, color: Color(0xFF00E676)),
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
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'ENDPOINT URL',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _urlCtrl,
                  keyboardType: TextInputType.url,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'https://example.com/api/scan',
                    hintStyle: const TextStyle(color: Color(0xFF64748B)),
                    filled: true,
                    fillColor: const Color(0xFF11182C),
                    prefixIcon: const Icon(
                      Icons.link_rounded,
                      color: Color(0xFF00E5FF),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF1E293B)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFF00E5FF),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                const Text(
                  'HTTP METHOD',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
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
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: selected
                                  ? color.withAlpha(35)
                                  : const Color(0xFF11182C),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? color
                                    : const Color(0xFF1E293B),
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
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  m == 'POST'
                                      ? 'JSON Body'
                                      : 'Query Parameters',
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
                const SizedBox(height: 18),

                const Text(
                  'CUSTOM HEADER (OPSIONAL)',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _headerKeyCtrl,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Authorization / X-API-Key',
                          hintStyle: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                          filled: true,
                          fillColor: const Color(0xFF11182C),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _headerValCtrl,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Bearer token / secret',
                          hintStyle: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                          filled: true,
                          fillColor: const Color(0xFF11182C),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF11182C),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: SwitchListTile(
                    value: _autoSend,
                    activeThumbColor: const Color(0xFF00E5FF),
                    title: const Text(
                      'Auto-Send Saat Simpan Scan',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: const Text(
                      'Otomatis kirim data ke REST API begitu hasil scan disimpan',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                    onChanged: (v) => setState(() => _autoSend = v),
                  ),
                ),
                const SizedBox(height: 18),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1426),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FORMAT DATA YANG DIKIRIM',
                        style: TextStyle(
                          color: Color(0xFF00E5FF),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'POST: JSON { id, value, raw_text, scan_type, barcode_format, note, timestamp }\n'
                        'GET: ?id=...&value=...&scan_type=...&note=...&timestamp=...',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11.5,
                          height: 1.45,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

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
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      _testing
                          ? 'Mengirim Test $_method...'
                          : 'Test Kirim API ($_method)',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00E5FF),
                      side: const BorderSide(color: Color(0xFF00E5FF)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),

                if (_lastTestResult != null) ...[
                  const SizedBox(height: 14),
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
}
