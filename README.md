# Bali Driver & Guide Management System — versi pengembangan 2

## Fitur
- Login dengan akun tim (admin, operasional, driver, guide).
- Admin/operasional: kelola database driver, guide, booking, kalender, komisi, laporan.
- Driver/guide: dapat membaca booking yang ditugaskan kepadanya (setelah akun dihubungkan pada profil driver/guide).
- Admin: dapat mengatur peran anggota melalui menu Pengguna.
- Tautan WhatsApp langsung dari nomor kontak.
- Kalender bulanan booking.
- Komisi driver dan guide serta status pembayaran.
- Link dokumen kendaraan dan masa berlaku dokumen.
- Export CSV untuk data yang sedang dibuka.

## Setup
1. Buat project di https://supabase.com (region Singapore jika tersedia).
2. Di SQL Editor jalankan seluruh `schema.sql`.
3. Di Project Settings > API salin Project URL dan anon/public key.
4. Isi keduanya pada konstanta `CONFIG` di awal script `index.html`. Jangan pernah pakai service_role key di browser.
5. Di Authentication > Users, invite/buat akun staf. Trigger otomatis membuat profil baru dengan peran default `driver`.
6. Jadikan akun pertama sebagai admin lewat SQL Editor:
   `update public.profiles set role='admin', full_name='Nama Admin' where email='email-admin-anda';`
7. Login sebagai admin. Buka menu Pengguna untuk mengatur peran `admin`, `ops`, `driver`, atau `guide`.
8. Pada menu Driver/Guide, hubungkan data orang dengan akun staf melalui kolom "Akun pengguna terkait". Driver/guide kemudian dapat login dan melihat booking yang ditugaskan.
9. Hosting file `index.html` pada Netlify, Cloudflare Pages, atau hosting web statis. Bagikan URL yang sama ke tim.

## Definisi peran
- `admin`: semua akses dan pengelolaan peran.
- `ops`: kelola driver, guide, booking dan laporan operasional.
- `driver`: hanya baca booking yang ditugaskan ke data driver yang terhubung.
- `guide`: hanya baca booking yang ditugaskan ke data guide yang terhubung.

## Penting sebelum go-live
- SQL RLS membatasi akses di database, bukan hanya menyembunyikan menu UI.
- User baru default `driver` agar pendaftaran tidak otomatis memberi hak operasional. Buat user lewat invite/admin, lalu tetapkan perannya.
- Admin dapat mengubah role di menu Pengguna. Jangan berikan role admin kepada semua orang.
- Driver/guide pada versi ini belum dapat mengubah status booking; perubahan status dilakukan staf operasional.
- Link dokumen kendaraan harus berupa URL ke penyimpanan yang aksesnya dibatasi. Hindari link publik untuk KTP atau dokumen pribadi. Versi ini tidak mengunggah file langsung.
- Untuk nomor WhatsApp, masukkan nomor internasional dengan kode negara (contoh Indonesia: 6281234567890) agar link WhatsApp tepat.
- Kalender dan komisi mengikuti data booking yang tersimpan. Uji dengan data dummy dan akun masing-masing peran sebelum dipakai untuk operasional sungguhan.
