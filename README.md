# SnapLog OCR — Offline Camera Field Logger

Aplikasi Android untuk memindai angka, nomor seri, meteran, atau label langsung dari kamera (**100% offline** menggunakan **Google ML Kit Text Recognition**), menyimpannya ke tabel log lokal beserta potongan bukti foto, lalu mengekspornya ke file **CSV (Excel)** atau berbagi ke WhatsApp.

## Fitur Utama
- **Kamera Live + Kotak Fokus ROI:** Bidik area teks/angka tertentu saja; gambar otomatis di-crop sesuai kotak fokus sebelum diproses OCR.
- **Filter Scan Pintar:** Pilihan mode `Semua Teks`, `Angka Saja`, atau `Kode / Serial` + opsi *Boost Kontras* untuk kondisi cahaya redup atau permukaan sulit.
- **Konfirmasi & Quick Edit:** Hasil scan langsung muncul dengan pratinjau potongan foto agar mudah dikoreksi 1 tap sebelum disimpan.
- **Tabel Log Lokal + Bukti Foto:** Data tersimpan offline di perangkat lengkap dengan *timestamp*, kategori, catatan, dan foto bukti yang bisa diperbesar.
- **Ekspor CSV 1 Klik:** Buat file `.csv` kompatibel Excel (dengan UTF-8 BOM) dan langsung bagikan ke WhatsApp, Email, atau Google Drive.
- **Auto-Build APK (GitHub Actions):** Push ke `main` otomatis merilis APK di **GitHub Releases** dan mengirim notifikasi ke **Telegram**.
