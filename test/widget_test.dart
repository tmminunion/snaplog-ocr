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

    // Different reading resets streak
    final mismatch = tracker.feed('SN-8890', now: t0.add(const Duration(milliseconds: 500)));
    expect(mismatch.shouldCommit, isFalse);
    expect(mismatch.streak, equals(1));

    // 3 identical frames commit
    expect(tracker.feed('SN-8899', now: t0.add(const Duration(milliseconds: 750))).streak, equals(1));
    expect(tracker.feed('SN-8899', now: t0.add(const Duration(milliseconds: 1000))).streak, equals(2));
    final f3 = tracker.feed('SN-8899', now: t0.add(const Duration(milliseconds: 1250)));
    expect(f3.shouldCommit, isTrue);

    // Same value within cooldown does not re-commit
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
      'https://api.example.com/hook?token=abc',
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
