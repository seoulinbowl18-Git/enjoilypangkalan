// Send SMS Hook Supabase Auth → kirim kode OTP lewat WhatsApp (Fonnte).
// Supabase memanggil fungsi ini setiap kali aplikasi memanggil signInWithOtp(phone).
//
// Secret yang dibutuhkan (Dashboard → Edge Functions → Secrets):
//   FONNTE_TOKEN          token device dari fonnte.com
//   SEND_SMS_HOOK_SECRET  secret dari Authentication → Hooks → Send SMS hook ("v1,whsec_...")
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";

type HookPayload = { user: { phone: string }; sms: { otp: string } };

const fail = (status: number, message: string) =>
  new Response(JSON.stringify({ error: { http_code: status, message } }), {
    status,
    headers: { "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  const token = Deno.env.get("FONNTE_TOKEN");
  const hookSecret = Deno.env.get("SEND_SMS_HOOK_SECRET");
  if (!token || !hookSecret) return fail(500, "FONNTE_TOKEN / SEND_SMS_HOOK_SECRET belum diisi");

  // Pastikan yang memanggil benar-benar Supabase Auth
  const body = await req.text();
  let payload: HookPayload;
  try {
    const wh = new Webhook(hookSecret.replace("v1,whsec_", ""));
    payload = wh.verify(body, Object.fromEntries(req.headers)) as HookPayload;
  } catch {
    return fail(401, "Signature hook tidak valid");
  }

  // Supabase menyimpan nomor tanpa "+", mis. 6281234567890
  const target = payload.user.phone.replace(/\D/g, "");
  const form = new FormData();
  form.append("target", target);
  form.append(
    "message",
    `Kode masuk Enjoily Pangkalan: *${payload.sms.otp}*\n\nJangan berikan kode ini ke siapa pun. Berlaku 5 menit.`,
  );

  const res = await fetch("https://api.fonnte.com/send", {
    method: "POST",
    headers: { Authorization: token },
    body: form,
  });
  const result = await res.json().catch(() => ({}));
  if (!res.ok || result.status !== true) {
    console.error("Fonnte gagal", res.status, result);
    return fail(502, `Gagal kirim WhatsApp: ${result.reason ?? res.statusText}`);
  }
  return new Response("{}", { headers: { "Content-Type": "application/json" } });
});
