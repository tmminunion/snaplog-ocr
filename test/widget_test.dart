import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snaplog_ocr/main.dart';
import 'package:snaplog_ocr/models/scan_entry.dart';
import 'package:snaplog_ocr/services/api_service.dart';
import 'package:snaplog_ocr/services/log_repository.dart';
import 'package:snaplog_ocr/services/scan_stability.dart';

void main() {
  test('applyOcrFilter extracts numbers and serial codes cleanly', () {
    expect(
      applyOcrFilter('Meter: 1245.8 kWh\nOK', OcrFilterMode.numbersOnly),
      equals('1245.8'),
    );
    expect(
      applyOcrFilter('sn: ub-2026/a1!@#', OcrFilterMode.serialCode),
      equals('SN UB-2026/A1'),
    );
    expect(
      applyOcrFilter('Line 1\n  Line 2  ', OcrFilterMode.all),
      equals('Line 1 Line 2'),
    );
  });

  test('StabilityTracker commits on 3 consecutive identical frames and cools down', () {
    final tracker = StabilityTracker(
      requiredFrames: 3,
      cooldown: const Duration(seconds: 2),
    );
    final t0 = DateTime(2026, 11, 27, 21, 0, 0);

    final f1 = tracker.feed('SN-8899', now: t0);
    expect(f1.shouldCommit, isFalse);
    expect(f1.streak, equals(1));

    final f2 = tracker.feed('SN-8899', now: t0.add(const Duration(milliseconds: 250)));
    expect(f2.shouldCommit, isFalse);
    expect(f2.streak, equals(2));

    final mismatch = tracker.feed('SN-8890', now: t0.add(const Duration(milliseconds: 500)));
    expect(mismatch.shouldCommit, isFalse);
    expect(mismatch.streak, equals(1));

    expect(tracker.feed('SN-8899', now: t0.add(const Duration(milliseconds: 750))).streak, equals(1));
    expect(tracker.feed('SN-8899', now: t0.add(const Duration(milliseconds: 1000))).streak, equals(2));
    final f3 = tracker.feed('SN-8899', now: t0.add(const Duration(milliseconds: 1250)));
    expect(f3.shouldCommit, isTrue);

    final dup = tracker.feed('SN-8899', now: t0.add(const Duration(milliseconds: 1800)));
    expect(dup.shouldCommit, isFalse);
    expect(dup.inCooldown, isTrue);
  });

  test('BarcodeCooldownTracker prevents duplicate reads within cooldown window', () {
    final tracker = BarcodeCooldownTracker(cooldown: const Duration(seconds: 2));
    final t0 = DateTime(2026, 11, 27, 21, 0, 0);

    expect(tracker.shouldAccept('QR-100', now: t0), isTrue);
    expect(tracker.shouldAccept('QR-100', now: t0.add(const Duration(milliseconds: 900))), isFalse);
    expect(tracker.shouldAccept('QR-200', now: t0.add(const Duration(milliseconds: 1000))), isTrue);
    expect(tracker.shouldAccept('QR-200', now: t0.add(const Duration(milliseconds: 3500))), isTrue);
  });

  test('ApiService manages multiple APIs with single active profile (CRUD)', () async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiService();

    final s1 = await api.upsertProfile(
      const ApiConfig(
        id: 'api_1',
        name: 'Server A',
        endpointUrl: 'https://example.com/a',
        method: 'POST',
      ),
    );
    expect(s1.profiles.length, equals(1));
    expect(s1.activeId, equals('api_1'));

    final s2 = await api.upsertProfile(
      const ApiConfig(
        id: 'api_2',
        name: 'Server B',
        endpointUrl: 'https://example.com/b',
        method: 'GET',
      ),
    );
    expect(s2.profiles.length, equals(2));
    expect(s2.activeId, equals('api_1')); // Still only api_1 active

    // Switch active to api_2
    final s3 = await api.setActiveProfile('api_2');
    expect(s3.activeProfile?.id, equals('api_2'));
    expect(s3.activeProfile?.method, equals('GET'));

    // Edit api_2
    final s4 = await api.upsertProfile(
      s3.activeProfile!.copyWith(name: 'Server B Updated'),
    );
    expect(s4.activeProfile?.name, equals('Server B Updated'));

    // Delete active profile clears activeId
    final s5 = await api.deleteProfile('api_2');
    expect(s5.profiles.length, equals(1));
    expect(s5.activeId, isNull);
  });

  test('ApiService builds dynamic custom payload with ID generator & templates', () {
    final api = ApiService();
    final entry = ScanEntry(
      id: 'local_1',
      text: 'PART-7788',
      rawText: 'PART-7788',
      note: 'Shift 1',
      filterMode: 'serialCode',
      scanType: 'qr',
      barcodeFormat: 'QR_CODE',
      imagePath: null,
      createdAt: DateTime(2026, 11, 27, 21, 30, 0),
    );

    const cfg = ApiConfig(
      id: 'api_custom',
      name: 'Custom',
      endpointUrl: 'https://example.com/hook',
      method: 'POST',
      customFields: [
        ApiCustomField(key: 'req_id', type: ApiFieldType.randomString, value: 'SL-'),
        ApiCustomField(key: 'kode', type: ApiFieldType.scanValue),
        ApiCustomField(key: 'line', type: ApiFieldType.staticValue, value: 'UB-ASSY-{{value}}'),
        ApiCustomField(key: 'jenis', type: ApiFieldType.scanType),
      ],
    );

    final payload = api.buildPayload(
      entry,
      cfg,
      randomGenerator: (prefix) => '${prefix}ABCD1234',
    );

    expect(payload['req_id'], equals('SL-ABCD1234'));
    expect(payload['kode'], equals('PART-7788'));
    expect(payload['line'], equals('UB-ASSY-PART-7788'));
    expect(payload['jenis'], equals('qr'));

    final generated = generateRandomIdString(length: 12, prefix: 'ID-');
    expect(generated.startsWith('ID-'), isTrue);
    expect(generated.length, equals(15));
  });

  test('buildCsvContent includes scanType, barcodeFormat, and API status without category', () {
    final entries = [
      ScanEntry(
        id: '1',
        text: 'PART-99, REV "B"',
        rawText: 'PART-99, REV "B"',
        note: 'Line A',
        filterMode: 'barcode',
        scanType: 'qr',
        barcodeFormat: 'QR_CODE',
        imagePath: '/tmp/scan_1.jpg',
        createdAt: DateTime(2026, 11, 27, 19, 30, 0),
        apiSynced: true,
        apiStatusCode: 200,
      ),
    ];

    final csv = buildCsvContent(entries);
    expect(csv.startsWith('\uFEFFNo,Timestamp,Tipe,Format,Hasil_Scan'), isTrue);
    expect(csv.contains('QR,QR_CODE'), isTrue);
    expect(csv.contains('"PART-99, REV ""B"""'), isTrue);
    expect(csv.contains('SENT (200)'), isTrue);
  });

  test('ApiService builds GET query URI preserving existing params', () {
    final api = ApiService();
    final uri = api.buildGetUri(
      'https://example.com/hook?token=abc',
      {'value': '12345', 'scan_type': 'barcode'},
    );
    expect(uri.queryParameters['token'], equals('abc'));
    expect(uri.queryParameters['value'], equals('12345'));
    expect(uri.queryParameters['scan_type'], equals('barcode'));
  });

  test('LogRepository adds, updates, and deletes entries locally', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LogRepository();
    await repo.load();

    final entry = ScanEntry(
      id: 'e1',
      text: '10452',
      rawText: '10452',
      note: 'Panel 1',
      filterMode: 'numbersOnly',
      imagePath: null,
      createdAt: DateTime.now(),
    );

    await repo.addEntry(entry);
    expect(repo.entries.length, equals(1));

    await repo.updateEntry(entry.copyWith(text: '10455', apiSynced: true));
    expect(repo.entries.first.text, equals('10455'));
    expect(repo.entries.first.apiSynced, isTrue);

    await repo.deleteEntry('e1');
    expect(repo.entries, isEmpty);
  });

  testWidgets('SnapLogOcrApp renders clean home dashboard without categories',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SnapLogOcrApp());
    await tester.pumpAndSettle();

    expect(find.text('SNAPLOG OCR'), findsOneWidget);
    expect(find.text('SCAN OCR'), findsOneWidget);
    expect(find.text('QR / BAR'), findsOneWidget);
    expect(find.text('Belum Ada Log Scan'), findsOneWidget);
    expect(find.text('Meteran'), findsNothing);
  });
}
