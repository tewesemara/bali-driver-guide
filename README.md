# Bali Driver & Guide

Aplikasi web statis untuk pengelolaan Driver, Mitra, kunjungan, dan komisi. GitHub Pages menyajikan aplikasi dari root branch `main`. Perubahan diuji di branch `development/whatsapp-validation` sebelum dirilis.

## Akun dan pekerjaan

| Peran | Pekerjaan |
| --- | --- |
| Owner | Kelola Driver dan Mitra, tunjuk Admin Owner, tinjau klaim, serta lihat kunjungan, komisi, dan laporan lintas Mitra. Owner dapat menolak, menonaktifkan, dan mengaktifkan kembali Mitra. |
| Admin Owner | Kelola dan impor data Driver, kelola profil dan Admin Mitra, setujui pendaftaran Mitra, tinjau klaim, serta pantau kunjungan dan komisi. |
| Admin Mitra | Kelola profil Mitra sendiri. Setelah aktif, cari Driver, catat kunjungan beserta komisi, edit komisi, catat pembayaran, dan ajukan koreksi setelah pembayaran. Riwayat dan laporan mengikuti keanggotaan Mitra. |
| Driver | Daftar dengan nomor WhatsApp Indonesia dan konfirmasi email. Jika nomor sudah tercatat, lihat status klaim setelah login. Akun yang tertaut dapat melihat komisi sendiri dan memutuskan koreksi pembayaran yang diterima. |

Untuk menautkan Admin Mitra ke profil yang sudah dibuat oleh staf, buka **Data Mitra**, pilih **Tautkan Admin**, lalu masukkan email akun khusus yang sudah terverifikasi. Staf memeriksa identitas pemohon klaim dengan menghubungi nomor pada data Driver sebelum menyetujui klaim.

## Impor dan laporan

- Di tab pertama Excel gunakan kolom `Nama Driver` dan `WhatsApp`. Kolom opsional adalah `Kabupaten/Kota`, `Alamat`, `Jenis Kendaraan`, `Nomor Polisi`, dan `Nomor SIM`.
- Format WhatsApp sebagai teks agar awalan `0` dan digit tetap utuh. Format Indonesia `08…`, `62…`, dan `+62…` dinormalisasi. Impor menyediakan pratinjau, pilihan melewati atau memperbarui duplikat, dan hasil per kelompok maksimal 50 baris. Kolom yang tidak ada di file tidak menimpa data yang sudah tersimpan.
- Laporan dikelompokkan menurut tanggal kunjungan di Asia/Makassar. Pilih harian, bulanan, atau tahunan serta tahun yang diinginkan. Kolom komisi disetujui memakai koreksi terbaru yang telah disetujui Driver. Kolom pembayaran tercatat menyimpan nominal pembayaran awal. Ekspor menghasilkan berkas `.xlsx` untuk periode yang sedang ditampilkan.

## Pengujian dan rilis

- Jalankan frontend lokal dengan `python -m http.server 8765 --bind 127.0.0.1`. Jalankan `python tests/browser.py` dengan Playwright, Chromium, dan curl tersedia. Untuk Chromium sistem, isi `BDG_CHROMIUM` dengan lokasi executable. Pengujian browser menyimulasikan respons Supabase.
- Jalankan `psql -X -v ON_ERROR_STOP=1 -f tests/operations.sql` pada database uji terisolasi yang memuat skema terbaru dan dua migrasi di folder `supabase/migrations`. Skrip memakai data sintetis dan `ROLLBACK`. File `schema.sql` adalah skema historis untuk versi awal aplikasi.
- Migrasi pengembangan bergantung pada skema proyek Supabase yang sudah berjalan dan diterapkan sesuai urutan nama file. Riwayat migrasi terkait proyek sudah memiliki versi `20261128101313`. Verifikasi riwayat yang tampil sebelum menerapkan dua versi baru.
- Setelah persetujuan produksi, terapkan migrasi dan verifikasi fungsi database serta hak akses dengan akun uji. Setelah persetujuan merge, gabungkan branch pengembangan ke `main` dan verifikasi deployment Pages serta login dan pemulihan akun dari URL publik.

[Catatan pengerjaan dan pengujian](catatan-pengembangan.md)
