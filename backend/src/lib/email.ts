// OTP email delivery. Uses Resend if RESEND_API_KEY is set; otherwise logs the code to
// the console (dev). Never throws into the request path on provider failure beyond a
// generic error — OTP start always returns 204 (no account enumeration).

export async function sendOtpEmail(email: string, code: string): Promise<void> {
  const apiKey = process.env.RESEND_API_KEY;
  const from = process.env.OTP_FROM_EMAIL ?? "hello@legacy.app";

  if (!apiKey) {
    console.log(`[dev OTP] ${email} → ${code}`);
    return;
  }

  await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from,
      to: email,
      subject: "Your Legacy code",
      text: `Your Legacy verification code is ${code}. It expires in 10 minutes.`,
    }),
  });
}
