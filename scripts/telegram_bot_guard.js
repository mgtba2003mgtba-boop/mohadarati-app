// ── NUST Attendance Telegram Bot Security Guard (Webhook Watchdog & Auto-Healer) ──
const rawToken = process.env.TELEGRAM_BOT_TOKEN || Buffer.from('ODc2MDAxNzUzMjpBQUdQaVZCQTYtVFBuU253dXhHV0dpUjh3VEpsS1lUOHZTTQ==', 'base64').toString('utf8');
const BOT_TOKEN = rawToken.trim();
const OFFICIAL_WEBHOOK_URL = 'https://rlupqsmqwvidmwrvqrcc.supabase.co/functions/v1/telegram-webhook';
const SECRET_TOKEN = 'NUST_Attendance_SecToken_2026_988147';
const POLL_INTERVAL_MS = 10000; // Check every 10 seconds

console.log('🛡️ [BOT GUARD ACTIVE] Starting Telegram Webhook Watchdog & Auto-Healer...');

async function checkAndHealWebhook() {
  try {
    const res = await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/getWebhookInfo`);
    const data = await res.json();

    if (!data.ok) {
      console.error('[-] Error fetching webhook info:', data.description);
      return;
    }

    const currentUrl = data.result?.url || '';
    if (currentUrl !== OFFICIAL_WEBHOOK_URL) {
      console.warn(`[⚠️ ALERT] Webhook divergence detected! Current: "${currentUrl}". Healing now...`);
      const setRes = await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/setWebhook`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          url: OFFICIAL_WEBHOOK_URL,
          secret_token: SECRET_TOKEN,
          drop_pending_updates: true,
          allowed_updates: ['message', 'callback_query']
        })
      });
      const setData = await setRes.json();
      if (setData.ok) {
        console.log(`[✅ HEALED] Webhook successfully restored and locked to official Supabase endpoint with secret_token!`);
      } else {
        console.error('[-] Failed to reset webhook:', setData.description);
      }
    }
  } catch (err) {
    console.error('[-] Watchdog network error:', err.message);
  }
}

// Initial check
checkAndHealWebhook();

// Recurring interval
setInterval(checkAndHealWebhook, POLL_INTERVAL_MS);
