# Scan2API — OCR, QR & Barcode to REST API

Aplikasi Android **offline-first** untuk memindai **teks kamera (OCR)**, **QR Code**, dan **Barcode** secara otomatis menggunakan **Google ML Kit**, menyimpan riwayat log lokal, mengekspor ke **CSV (Excel)**, serta mengirim data langsung ke **REST API (`POST` / `GET`)** dengan payload dinamis.

## Fitur Utama
- **Live OCR + Auto-Save 3 Frame:** Bidik teks/angka di dalam kotak fokus ROI; teks dibaca secara *real-time* dan otomatis tersimpan saat stabil 3 frame berturut-turut (dengan filter `Semua Teks`, `Angka Saja`, dan `Kode / Serial`).
- **Auto-Capture QR & Barcode:** Deteksi otomatis QR Code, Code128, Code39, EAN-13, UPC, DataMatrix, dan PDF417 tanpa perlu tekan shutter, lengkap dengan anti-duplikat untuk scan beruntun.
- **Multi-API List (CRUD + Single Active):** Simpan banyak konfigurasi REST API (tambah, edit, hapus) dan pilih 1 endpoint aktif kapan saja.
- **Dynamic Payload (`POST` / `GET`) + ID Generator:** Susun field *key-value* bebas dengan tombol `+`, termasuk generator ID string acak, nilai statis, dan placeholder dinamis (`{{value}}`, `{{random_id}}`, `{{timestamp}}`, `{{scan_type}}`, `{{note}}`), plus *Custom Header* & tombol *Test API*.
- **Ekspor CSV 1 Klik:** Ekspor seluruh log lokal ke file `.csv` (UTF-8 BOM, rapi di Excel) dan bagikan langsung ke WhatsApp, Email, atau Google Drive.
- **CI/CD Otomatis (GitHub Actions):** Build *signed* APK & Play Store AAB otomatis, rilis ke GitHub Releases, sinkronisasi listing Play Store, dan kirim notifikasi ke Telegram.
