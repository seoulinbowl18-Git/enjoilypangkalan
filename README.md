# Enjoily Pangkalan

Aplikasi Flutter (Android, iOS, web) untuk pangkalan mobil listrik.

```bash
flutter run                          # mode demo, data contoh, tanpa login
flutter run --dart-define=DEMO=false # pakai Supabase + halaman login
```

## Login OTP WhatsApp (Fonnte)

Supabase tidak mengirim OTP sendiri. Lewat **Send SMS Hook**, kodenya diteruskan
ke Edge Function `send-otp-fonnte`, lalu dikirim ke WhatsApp lewat Fonnte.
Token Fonnte hanya disimpan di Supabase, tidak pernah di dalam aplikasi.

1. **Deploy fungsi** (sekali, dari folder proyek):
   ```bash
   npx supabase login
   npx supabase functions deploy send-otp-fonnte --project-ref tbjcfdwkqdrwsnzzbhpo --no-verify-jwt
   ```
2. **Authentication → Sign In / Providers → Phone**: aktifkan *Enable phone provider*.
   Pilihan SMS provider (Twilio dll.) boleh dibiarkan, karena hook yang mengirim.
3. **Authentication → Hooks → Send SMS hook**: aktifkan, tipe *HTTPS*, URL
   `https://tbjcfdwkqdrwsnzzbhpo.supabase.co/functions/v1/send-otp-fonnte`.
   Klik *Generate secret* dan salin nilainya (`v1,whsec_...`).
4. **Edge Functions → Secrets**: tambahkan
   - `FONNTE_TOKEN` = token device dari fonnte.com
   - `SEND_SMS_HOOK_SECRET` = secret dari langkah 3

## Login Google

- **Authentication → Providers → Google**: isi Client ID & Secret dari Google Cloud.
- **Authentication → URL Configuration → Redirect URLs**: tambahkan
  `io.supabase.enjoilypangkalan://login-callback/` (Android & iOS).
  Belum perlu alamat web. Untuk mencoba di Chrome, jalankan
  `flutter run -d chrome --web-port=3000 --dart-define=DEMO=false` dan tambahkan
  `http://localhost:3000` juga.
