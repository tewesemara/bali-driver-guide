# Catatan pengembangan 28 November 2026

## Pemeriksaan awal

- GitHub dapat diakses. Branch pengembangan berawal dari `19fb007`. GitHub Pages aktif dan menggunakan root branch `main`.
- Skema Supabase aktual memuat 11 tabel publik dengan RLS aktif pada semuanya. Kode awal sudah memiliki login empat peran, pengelolaan profil Mitra, pencarian Driver, pencatatan kunjungan dan komisi, serta RPC peninjauan klaim.
- Antarmuka klaim, riwayat kunjungan, laporan, dan ekspor belum tersambung. Saat koreksi kedua diminta setelah pembayaran, nominal awal pembayaran masih dipakai sebagai dasar. Mitra yang dibuat staf belum dapat langsung ditautkan ke akun Admin Mitra dari aplikasi.
- Audit produksi memakai metadata katalog dan Supabase Advisors. Advisor keamanan mencatat fungsi `SECURITY DEFINER` yang dapat dipanggil akun terautentikasi, proteksi kata sandi bocor pada Auth, dan tabel koreksi dengan RLS tanpa kebijakan akses langsung. Akses koreksi berjalan melalui fungsi yang memeriksa peran, keanggotaan Mitra, dan penerima pembayaran. Implementasi fungsi berhak khusus yang baru atau diperbarui dipindah ke skema di luar Data API. Advisor performa mencatat indeks FK yang belum tersedia, kebijakan permisif yang bertumpuk, dan indeks yang belum digunakan.

## Pekerjaan di branch pengembangan

| Cakupan | Hasil |
| --- | --- |
| WhatsApp dan impor | Validasi format Indonesia pada pendaftaran dan input Driver. Impor membaca nomor dengan awalan nol yang hilang dari sel angka, menampilkan pratinjau, dan menangani duplikat secara atomik di tiap kelompok. |
| Claim Account Driver | Konfirmasi email memicu pembuatan data Driver baru atau klaim bila nomor sudah ada. Staf dapat memeriksa dan memutus klaim. Driver melihat status klaim dan alasan penolakan. |
| Empat dashboard dan Mitra | Dashboard mengikuti peran. Staf dapat menautkan akun khusus terverifikasi ke Mitra. Owner dapat mengaktifkan kembali Mitra yang ditangguhkan. Tampilan tabel menyediakan gulir horizontal di layar sempit. |
| Kunjungan, komisi dan koreksi | Kunjungan dan komisi baru disimpan dalam satu transaksi. Mitra dapat mengedit komisi sebelum pembayaran dan mengajukan koreksi komisi lunas. Driver penerima memutus koreksi. Saat akun belum tertaut, Admin Mitra melihat instruksi pendaftaran dan klaim. |
| Laporan dan isolasi | Riwayat kunjungan, visualisasi harian, bulanan, tahunan, dan ekspor Excel. Query Mitra memeriksa keanggotaan di database. |
| Publikasi | Konfigurasi Pages yang aktif sudah diverifikasi. Migrasi dan frontend disiapkan di branch pengembangan. |

## Commit pengembangan

- `0619984` menyelesaikan klaim Driver, koreksi, impor Excel, kunjungan, dan laporan.
- `45c14d9` menyelesaikan penautan Admin Mitra dan pengaktifan kembali Mitra.
- `064eeea` membatasi fungsi database berhak khusus ke skema internal serta menambahkan pengujian browser dan catatan rilis.

## Hasil pengujian

- PostgreSQL 17 lokal dengan struktur tabel, kebijakan, constraint, grant, dan fungsi dari metadata produksi serta data sintetis. Kedua migrasi berhasil diterapkan pada salinan tersebut. `tests/operations.sql` mencakup 57 pemeriksaan dan berakhir dengan `ROLLBACK`.
- PostgREST lokal memverifikasi bentuk respons dan hak akses API untuk impor, klaim, kunjungan, pembayaran, koreksi, dan laporan. Dua permintaan impor bersamaan untuk nomor yang sama menghasilkan satu pembuatan dan satu lewati.
- Chromium menguji Owner, Admin Owner, Admin Mitra, dan Driver pada lebar 1440 px serta 390 px dengan respons API yang disimulasikan. Ekspor diverifikasi dengan membaca kembali isi workbook.
- GoTrue dan kotak email Mailpit lokal memverifikasi pendaftaran, konfirmasi, klaim untuk data yang sudah ada, pembuatan data Driver baru, login, dan pemulihan kata sandi. Chromium yang terhubung ke GoTrue dan PostgREST lokal juga memverifikasi status klaim, pemulihan sesi setelah muat ulang, dan logout.
- Verifikasi email produksi dan integrasi pada URL GitHub Pages menunggu penerapan produksi. Penerapan migrasi produksi, perubahan konfigurasi Auth produksi, dan merge ke `main` membutuhkan persetujuan.

## Rujukan

- [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Advisor fungsi publik dengan hak pembuat](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)
- [Proteksi kata sandi bocor](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)
