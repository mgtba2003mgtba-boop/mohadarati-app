// ── NUST Attendance Telegram Bot Security Guard (Webhook Watchdog & Auto-Healer) ──
const rawToken = process.env.TELEGRAM_BOT_TOKEN || Buffer.from('ODc2MDAxNzUzMjpBQUhjb2NvYkQxLU1jTVpYcV9Yc2VMUmZqRHNQUWhZbUsxQQ==', 'base64').toString('utf8');
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

// Recurring interval
async function checkAndHealCommands() {
  try {
    const res = await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/getMyCommands`);
    const data = await res.json();
    if (data.ok && (!data.result || data.result.length === 0)) {
      console.warn(`[⚠️ ALERT] Bot commands missing! Re-registering commands & menu button...`);
      await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/setMyCommands`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          commands: [
            { command: 'start', description: 'القائمة الرئيسية ونظام البصمة' },
            { command: 'app', description: 'تحميل وتثبيت تطبيق محاضراتي' },
            { command: 'card', description: 'بطاقتي الأكاديمية والقيد' },
            { command: 'id', description: 'نسخ المعرف الجامعي فوراً' },
            { command: 'support', description: 'الدعم الفني والمساعدة' }
          ]
        })
      });
      await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/setChatMenuButton`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ menu_button: { type: 'commands' } })
      });
      console.log(`[✅ HEALED] Bot commands and Menu Button successfully restored!`);
    }
  } catch (err) {
    console.error('[-] Command watchdog network error:', err.message);
  }
}

// Initial check
checkAndHealWebhook();
checkAndHealCommands();

// Recurring interval
setInterval(() => {
  checkAndHealWebhook();
  checkAndHealCommands();
}, POLL_INTERVAL_MS);

