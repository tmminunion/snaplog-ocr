import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snaplog_ocr/main.dart';
import 'package:snaplog_ocr/models/scan_entry.dart';
import 'package:snaplog_ocr/services/api_service.dart';
import 'package:snaplog_ocr/services/log_repository.dart';

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

  test('buildCsvContent includes scanType, barcodeFormat, and API status', () {
    final entries = [
      ScanEntry(
        id: '1',
        text: 'PART-99, REV "B"',
        rawText: 'PART-99, REV "B"',
        category: 'QR / Barcode',
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
    expect(csv.startsWith('\uFEFFNo,Timestamp,Tipe,Format,Kategori'), isTrue);
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
      category: 'Meteran',
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

  testWidgets('SnapLogOcrApp renders home dashboard with QR & OCR buttons',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SnapLogOcrApp());
    await tester.pumpAndSettle();

    expect(find.text('SNAPLOG OCR'), findsOneWidget);
    expect(find.text('SCAN OCR'), findsOneWidget);
    expect(find.text('QR/BAR'), findsOneWidget);
    expect(find.text('Belum Ada Log Scan'), findsOneWidget);
  });
}
