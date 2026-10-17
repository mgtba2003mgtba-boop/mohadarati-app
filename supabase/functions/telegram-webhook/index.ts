// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This code is running on Supabase Edge Functions (Deno).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS'
};
const TELEGRAM_API = 'https://api.telegram.org/bot';
const APK_FILE_ID = 'BQADAgADc7EAAlcvkEr4UYPrrkl-ZgI';
const IOS_CONFIG_FILE_ID = 'BQACAgIAAxkDAAI6DGrP1TOyxB1MG6R6pgblY3xYbmc_AAJJowACYkqBSoPUmsJkUUNGPQQ';
const IOS_GUIDE_FILE_ID = 'CgACAgIAAxkDAAI6i2rP-ZNOURKYV1SPv6wLh7ToHDAjAAJ5pQACYkqBSpHFCPiQdXgfPQQ';
const dayArabic = {
  saturday: 'السبت',
  sunday: 'الأحد',
  monday: 'الاثنين',
  tuesday: 'الثلاثاء',
  wednesday: 'الأربعاء',
  thursday: 'الخميس',
  friday: 'الجمعة'
};
Deno.serve(async (req)=>{
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: corsHeaders
    });
  }
  try {
    const botToken = Deno.env.get('TELEGRAM_BOT_TOKEN') || atob('ODc2MDAxNzUzMjpBQUhjb2NvYkQxLU1jTVpYcV9Yc2VMUmZqRHNQUWhZbUsxQQ==');
    const body = await req.json();

    // ── 1. Direct API Invocation (محمي بتصريح أمني صارم لمنع العبث بالبوت) ─────
    if (body.action) {
      const authHeader = req.headers.get('authorization') || '';
      const customKey = req.headers.get('x-admin-key') || '';
      const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
      const adminKey = Deno.env.get('ADMIN_KEY') || 'nust_admin_sec_2026_att';

      const isAuthorized =
        (Boolean(serviceRoleKey) && authHeader.includes(serviceRoleKey)) ||
        (Boolean(customKey) && customKey === adminKey) ||
        (authHeader.replace('Bearer ', '').trim() === adminKey);

      if (!isAuthorized) {
        return new Response(JSON.stringify({ error: 'Unauthorized: Administrative actions require valid authentication key.' }), {
          status: 401,
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        });
      }
    }

    // ── 1.1. التحصين الأمني الصارم لرسائل تيليجرام الواردة (Secret Token Validation) ───
    const tgSecretToken = Deno.env.get('TELEGRAM_SECRET_TOKEN') || 'NUST_Attendance_SecToken_2026_988147';
    if (!body.action) {
      const incomingSecret = req.headers.get('x-telegram-bot-api-secret-token');
      if (incomingSecret !== tgSecretToken) {
        return new Response(JSON.stringify({ error: 'Forbidden: Invalid or missing secret token' }), {
          status: 403,
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        });
      }
    }

    if (body.action === 'get_webhook_info') {
      const res = await fetch(`${TELEGRAM_API}${botToken}/getWebhookInfo`);
      const data = await res.json();
      return new Response(JSON.stringify(data), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
    if (body.action === 'set_webhook' || body.action === 'enforce_webhook') {
      const webhookUrl = body.url || 'https://rlupqsmqwvidmwrvqrcc.supabase.co/functions/v1/telegram-webhook';
      const res = await fetch(`${TELEGRAM_API}${botToken}/setWebhook`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          url: webhookUrl,
          secret_token: tgSecretToken,
          drop_pending_updates: true,
          allowed_updates: ['message', 'callback_query']
        })
      });
      const data = await res.json();
      return new Response(JSON.stringify(data), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
    if (body.action === 'set_commands' || body.action === 'init') {
      const res = await fetch(`${TELEGRAM_API}${botToken}/setMyCommands`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          commands: [
            {
              command: 'start',
              description: 'نظام الحضور وتسجيل البصمة'
            },
            {
              command: 'app',
              description: 'تحميل وتثبيت تطبيق محاضراتي'
            }
          ]
        })
      });
      const data = await res.json();
      return new Response(JSON.stringify(data), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
    if (body.action === 'send_direct_message' || body.action === 'send_notification' || body.action === 'send_broadcast') {
      const { chat_id, message, inline_keyboard } = body;
      if (!chat_id || !message) {
        return new Response(JSON.stringify({
          error: 'chat_id and message are required'
        }), {
          status: 400,
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        });
      }
      const res = await sendTelegramMessage(botToken, chat_id, message, inline_keyboard ? {
        inline_keyboard
      } : undefined);
      return new Response(JSON.stringify(res), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
    // ── 2. Handle Telegram Webhook Updates ────────────────────────────────────────
    const update = body;
    // Handle Callback Queries (Button Clicks)
    if (update.callback_query) {
      const cb = update.callback_query;
      const chatId = String(cb.message?.chat.id || cb.from.id);
      const data = cb.data || '';
      // 1. Immediately dismiss loading spinner on user's Telegram client
      try {
        await answerCallbackQuery(botToken, cb.id);
      } catch  {}
      if (data.startsWith('day:')) {
        const selectedDay = data.replace('day:', '').trim();
        const schedMsg = await getStudentScheduleForDay(chatId, selectedDay);
        const keyboard = await getStudentScheduleInlineKeyboard(chatId);
        await sendTelegramMessage(botToken, chatId, schedMsg, keyboard);
        return new Response(JSON.stringify({
          ok: true
        }), {
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        });
      }
      if (data.startsWith('pick_student:')) {
        const pickedId = data.replace('pick_student:', '').trim();
        const student = await findAndLinkStudentByNameOrId(pickedId, chatId);
        if (student && !student.isMultiple && !student.isAlreadyLinkedToOther) {
          const hasFace = Boolean(student.face_embedding && student.face_embedding.length > 0 || student.photo_url);
          if (!hasFace) {
            const regUrl = buildStudentRegistrationUrl(student);
            const qrPhotoUrl = `https://quickchart.io/qr?text=${encodeURIComponent(regUrl)}&size=800&margin=4&ecLevel=H&centerImageUrl=${encodeURIComponent('https://nnnnnnn-chi.vercel.app/college-logo.png')}&centerImageSizeRatio=0.22`;
            const cleanStage = (student.stage || '').replace(/المرحلة/g, '').replace(/السنة/g, '').replace(/الدراسية/g, '').trim();
            const stageDisplay = cleanStage ? `المرحلة ${cleanStage}` : student.stage || '';
            const academicSubtitle = [
              student.department || '',
              stageDisplay,
              student.section ? `شعبة (${student.section})` : ''
            ].filter(Boolean).join(' • ');
            const caption = `🏛️ <b>الجامعة الوطنية للعلوم والتكنولوجيا</b>\n` + `📍 <b>الكلية التقنية الهندسية</b>\n` + `━━━━━━━━━━━━━━━━━━━━━\n` + `🎓 <b>بطاقة ورمز تسجيل الطالب</b>\n\n` + `👤 <b>${student.name}</b>\n` + `📚 <b>${academicSubtitle}</b>\n` + `🔢 <code>${student.id}</code>\n` + `━━━━━━━━━━━━━━━━━━━━━\n` + `📸 <b>لتسجيل وتوثيق بصمة وجهك:</b>\n` + `1️⃣ اضغط على الزر أدناه لفتح الكاميرا والتسجيل مباشرة.\n` + `2️⃣ أو امسح الباركود أعلاه بكاميرا هاتف آخر.`;
            await sendTelegramPhoto(botToken, chatId, qrPhotoUrl, caption, {
              inline_keyboard: [
                [
                  {
                    text: '📸 فتح الكاميرا والتسجيل مباشرة',
                    url: regUrl
                  }
                ]
              ]
            });
          } else {
            await sendTelegramMessage(botToken, chatId, `✅ <b>تم اختيار قيدك بنجاح</b>\n\n` + `• الطالب: <b>${student.name}</b>\n` + `• القسم: <b>${student.department}</b> — <b>${student.stage}</b>\n\n` + `بصمة وجهك مسجلة وستصلك إشعارات الحضور تلقائياً.`);
          }
        }
        return new Response(JSON.stringify({
          ok: true
        }), {
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        });
      }
      if (data === 'cmd:android') {
        await sendAndroidInstallGuide(botToken, chatId);
        return new Response(JSON.stringify({
          ok: true
        }), {
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        });
      }
      if (data === 'cmd:apk' || data === 'cmd:android') {
        await sendAndroidApkFile(botToken, chatId);
        return new Response(JSON.stringify({
          ok: true
        }), {
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        });
      }
      if (data === 'cmd:ios') {
        await sendIosInstallGuide(botToken, chatId);
        return new Response(JSON.stringify({
          ok: true
        }), {
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        });
      }
      if (data === 'cmd:app') {
        await sendAppOverviewMenu(botToken, chatId);
        return new Response(JSON.stringify({
          ok: true
        }), {
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        });
      }
      if (data === 'cmd:id') {
        const idMsg = await getStudentIdOnly(chatId);
        await sendTelegramMessage(botToken, chatId, idMsg);
        return new Response(JSON.stringify({
          ok: true
        }), {
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        });
      }
      if (data === 'cmd:card') {
        const profileMsg = await getStudentProfile(chatId);
        await sendTelegramMessage(botToken, chatId, profileMsg);
        return new Response(JSON.stringify({
          ok: true
        }), {
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        });
      }

      return new Response(JSON.stringify({
        ok: true
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
    const message = update.message;
    if (!message) {
      return new Response(JSON.stringify({
        ok: true
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
    const chatId = String(message.chat?.id);
    const text = (message.text || '').trim();
    const lower = text.toLowerCase().trim();

    // 1. Command: /id (إرسال رقم المعرف مجرداً تماماً بدون أي نص إضافي)
    if (lower.startsWith('/id') || lower === 'id' || lower === 'معرفي' || lower === 'كود' || lower === 'رقمي' || lower === 'معرف') {
      const idMsg = await getStudentIdOnly(chatId);
      await sendTelegramMessage(botToken, chatId, idMsg);
      return new Response(JSON.stringify({
        ok: true
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }

    // 2. Command: /android or apk (تحميل تطبيق الأندرويد APK مباشر)
    if (
      lower.startsWith('/android') ||
      lower.startsWith('/apk') ||
      lower === 'android' ||
      lower === 'apk' ||
      lower === 'اندرويد' ||
      lower === 'أندرويد' ||
      lower === 'تطبيق اندرويد' ||
      lower === 'تطبيق الأندرويد'
    ) {
      await sendAndroidInstallGuide(botToken, chatId);
      return new Response(JSON.stringify({
        ok: true
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }

    // 3. Command: /ios (تثبيت تطبيق محاضراتي على الآيفون بدون متصفح)
    if (
      lower.startsWith('/ios') ||
      lower === 'ios' ||
      lower === 'ايفون' ||
      lower === 'آيفون' ||
      lower === 'تطبيق ايفون' ||
      lower === 'تطبيق الآيفون'
    ) {
      await sendIosInstallGuide(botToken, chatId);
      return new Response(JSON.stringify({
        ok: true
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }

    // 4. Command: /app or app or /download (تثبيت وتحميل التطبيق لجميع الأنظمة)
    if (
      lower.startsWith('/app') ||
      lower === 'app' ||
      lower.startsWith('app ') ||
      lower.startsWith('/download') ||
      lower === 'download' ||
      lower.startsWith('/install') ||
      lower === 'install' ||
      lower === 'تطبيق' ||
      lower === 'تحميل' ||
      lower === 'تثبيت' ||
      lower === 'تنزيل' ||
      lower === 'برنامج' ||
      lower === 'محاضراتي' ||
      lower === 'تطبيق محاضراتي' ||
      lower === 'تحميل التطبيق' ||
      lower === 'رابط التطبيق' ||
      lower === 'حمل التطبيق' ||
      lower === 'تثبيت التطبيق'
    ) {
      await sendAppOverviewMenu(botToken, chatId);
      return new Response(JSON.stringify({
        ok: true
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
    // 3. Command: /card or /profile
    if (text.startsWith('/card') || text.startsWith('/profile') || text === 'بطاقتي') {
      const profileMsg = await getStudentProfile(chatId);
      await sendTelegramMessage(botToken, chatId, profileMsg);
      return new Response(JSON.stringify({
        ok: true
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }

    // 5. Command: /start
    if (text.startsWith('/start')) {
      const parts = text.split(' ');
      const studentId = parts.length > 1 ? parts[1].trim() : '';
      if (studentId === 'android' || studentId === 'apk') {
        await sendAndroidInstallGuide(botToken, chatId);
        return new Response(JSON.stringify({
          ok: true
        }), {
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        });
      }
      if (studentId === 'ios') {
        await sendIosInstallGuide(botToken, chatId);
        return new Response(JSON.stringify({
          ok: true
        }), {
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        });
      }
      if (studentId === 'app' || studentId === 'download' || studentId === 'install') {
        await sendAppOverviewMenu(botToken, chatId);
        return new Response(JSON.stringify({
          ok: true
        }), {
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        });
      }
      if (studentId === 'id' || studentId === 'get_code') {
        const idMsg = await getStudentIdOnly(chatId);
        await sendTelegramMessage(botToken, chatId, idMsg);
        return new Response(JSON.stringify({
          ok: true
        }), {
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        });
      }
      if (studentId === 'card') {
        const profileMsg = await getStudentProfile(chatId);
        await sendTelegramMessage(botToken, chatId, profileMsg);
        return new Response(JSON.stringify({
          ok: true
        }), {
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        });
      }
      if (studentId === 'today') {
        const todayMsg = await getStudentTodaySchedule(chatId);
        const keyboard = await getStudentScheduleInlineKeyboard(chatId);
        await sendTelegramMessage(botToken, chatId, todayMsg, keyboard);
        return new Response(JSON.stringify({
          ok: true
        }), {
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        });
      }
      if (studentId && !studentId.startsWith('reg_')) {
        const result = await findAndLinkStudentByNameOrId(studentId, chatId);
        if (result?.isAlreadyLinkedToOther) {
          await sendTelegramMessage(botToken, chatId, `🔒 <b>القيد موثق مسبقاً</b>\n\n` + `القيد الأكاديمي للطالب (<b>${result.student.name}</b>) مرتبط مسبقاً بحساب تيليجرام آخر.\n` + `راجع إدارة الكلية في حال واجهت مشكلة.`);
        } else if (result) {
          const student = result;
          const hasFace = Boolean(student.face_embedding && student.face_embedding.length > 0 || student.photo_url);
          if (!hasFace) {
            const regUrl = buildStudentRegistrationUrl(student);
            const qrPhotoUrl = `https://quickchart.io/qr?text=${encodeURIComponent(regUrl)}&size=800&margin=4&ecLevel=H&centerImageUrl=${encodeURIComponent('https://nnnnnnn-chi.vercel.app/college-logo.png')}&centerImageSizeRatio=0.22`;
            const cleanStage = (student.stage || '').replace(/المرحلة/g, '').replace(/السنة/g, '').replace(/الدراسية/g, '').trim();
            const stageDisplay = cleanStage ? `المرحلة ${cleanStage}` : student.stage || '';
            const academicSubtitle = [
              student.department || '',
              stageDisplay,
              student.section ? `شعبة (${student.section})` : ''
            ].filter(Boolean).join(' • ');
            const caption = `🏛️ <b>الجامعة الوطنية للعلوم والتكنولوجيا</b>\n` + `📍 <b>الكلية التقنية الهندسية</b>\n` + `━━━━━━━━━━━━━━━━━━━━━\n` + `🎓 <b>بطاقة ورمز تسجيل الطالب</b>\n\n` + `👤 <b>${student.name}</b>\n` + `📚 <b>${academicSubtitle}</b>\n` + `🔢 <code>${student.id}</code>\n` + `━━━━━━━━━━━━━━━━━━━━━\n` + `📸 <b>لتسجيل وتوثيق بصمة وجهك:</b>\n` + `1️⃣ اضغط على الزر أدناه لفتح الكاميرا والتسجيل مباشرة.\n` + `2️⃣ أو امسح الباركود أعلاه بكاميرا هاتف آخر.`;
            await sendTelegramPhoto(botToken, chatId, qrPhotoUrl, caption, {
              inline_keyboard: [
                [
                  {
                    text: '📸 فتح الكاميرا والتسجيل مباشرة',
                    url: regUrl
                  }
                ]
              ]
            });
          } else {
            await sendTelegramMessage(botToken, chatId, `🏛️ <b>الجامعة الوطنية للعلوم والتكنولوجيا</b>\n` + `أهلاً بك <b>${student.name}</b>\n` + `• القسم: <b>${student.department}</b> — <b>${student.stage}</b>\n\n` + `✅ <b>حسابك وبصمة وجهك مفعلان ومستعد لاستلام إشعارات الحضور.</b>`);
          }
        } else {
          await sendTelegramMessage(botToken, chatId, `⚠️ <b>لم يتم العثور على القيد</b>\n` + `يرجى إرسال <b>اسمك الرباعي كاملاً</b> أو المعرف الأكاديمي للربط.`);
        }
      } else {
        const student = await getStudentByChatId(chatId);
        if (student) {
          const welcomeMsg = `🏛️ <b>الجامعة الوطنية للعلوم والتكنولوجيا</b>\n` +
            `🤖 <b>نظام تسجيل الحضور وبصمة الوجه</b>\n` +
            `━━━━━━━━━━━━━━━━━━━━━\n` +
            `أهلاً بك يا <b>${student.name}</b> 🎓\n` +
            `• القسم: <b>${student.department}</b> — <b>${student.stage}</b>\n` +
            `• المعرف الأكاديمي: <code>${student.id}</code>\n\n` +
            `✅ <b>حسابك مرتبط وبصمتك موثقة بنجاح.</b>\n` +
            `ستصلك إشعارات تسجيل الحضور في القاعات والمختبرات تلقائياً.\n\n` +
            `📲 <i>لتحميل وتثبيت تطبيق محاضراتي، أرسل:</i> /app`;
          await sendTelegramMessage(botToken, chatId, welcomeMsg);
        } else {
          const unlinkedMsg = `🏛️ <b>الجامعة الوطنية للعلوم والتكنولوجيا</b>\n` +
            `📍 <b>الكلية التقنية الهندسية</b>\n` +
            `━━━━━━━━━━━━━━━━━━━━━\n` +
            `👋 <b>أهلاً وسهلاً بك في البوت الأكاديمي الرسمي</b> 🎓\n\n` +
            `لتسجيل حسابك وتوثيق قيدك واستلام إشعارات الحضور والمحاضرات:\n` +
            `✍️ <b>يرجى إرسال اسمك الرباعي كاملاً</b> هنا في المحادثة\n` +
            `<i>(مثال: علي محمد حسن كاظم)</i>\n` +
            `ليتم البحث عن قيدك الجامعي وربطه فوراً.\n\n` +
            `💡 <i>أو يمكنك إرسال رقمك الجامعي إن كان متوفراً لديك.</i>`;
          await sendTelegramMessage(botToken, chatId, unlinkedMsg, {
            inline_keyboard: [
              [
                {
                  text: '📲 تحميل وتثبيت تطبيق محاضراتي',
                  callback_data: 'cmd:app'
                }
              ]
            ]
          });
        }
      }
      return new Response(JSON.stringify({
        ok: true
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
    // 6. Command: /help or /menu
    if (text.startsWith('/help') || text.startsWith('/menu') || text === 'مساعدة' || text === 'أوامر' || text === 'اوامر') {
      const isLinked = await checkStudentLinked(chatId);
      if (isLinked) {
        const helpMsg = `🏛️ <b>الجامعة الوطنية للعلوم والتكنولوجيا</b>\n` + `🤖 <b>دليل واختصارات البوت الأكاديمي</b>\n` + `━━━━━━━━━━━━━━━━━━━━━\n` + `• <code>/app</code> ➔ تحميل وتثبيت تطبيق محاضراتي للهاتف\n` + `• <code>/start</code> ➔ نظام الحضور وتسجيل البصمة\n` + `• <code>/id</code> ➔ نسخ المعرف الجامعي فوراً\n` + `• <code>/card</code> ➔ بطاقتي الأكاديمية والقيد`;
        const keyboard = {
          inline_keyboard: [
            [
              {
                text: '📲 تحميل تطبيق محاضراتي',
                callback_data: 'cmd:app'
              }
            ],
            [
              {
                text: '🔢 نسخ المعرف الجامعي',
                callback_data: 'cmd:id'
              },
              {
                text: '💳 بطاقتي الأكاديمية',
                callback_data: 'cmd:card'
              }
            ],
            [
              {
                text: '💬 الدعم الفني والمساعدة',
                url: 'https://t.me/ii6689'
              }
            ]
          ]
        };
        await sendTelegramMessage(botToken, chatId, helpMsg, keyboard);
      } else {
        await sendTelegramMessage(botToken, chatId, `👋 <b>أهلاً بك!</b>\n\nيرجى كتابة <b>اسمك الرباعي كاملاً</b> ✍️ هنا في المحادثة للبحث عن قيدك الأكاديمي وربط حسابك فوراً.\n<i>(مثال: علي محمد حسن كاظم)</i>`, {
          inline_keyboard: [
            [
              {
                text: '📲 تحميل وتثبيت تطبيق محاضراتي',
                callback_data: 'cmd:app'
              }
            ],
            [
              {
                text: '💬 الدعم الفني والمساعدة',
                url: 'https://t.me/ii6689'
              }
            ]
          ]
        });
      }
      return new Response(JSON.stringify({
        ok: true
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }

    // 7. Command: /support
    if (text.startsWith('/support') || text === 'دعم' || text === 'الدعم الفني') {
      await sendTelegramMessage(botToken, chatId, `👨‍💻 <b>الدعم الفني والمساعدة المباشرة</b>\n\nلأي استفسار أو مشكلة تقنية، تواصل مباشرة مع المطور والمشرف:\n👉 <b>@ii6689</b>`, {
        inline_keyboard: [
          [{ text: '💬 تواصل مع الدعم الفني', url: 'https://t.me/ii6689' }]
        ]
      });
      return new Response(JSON.stringify({ ok: true }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // 4. Text Message: Try to link by Exact Name or Student ID
    if (text.length >= 2) {
      const isAlreadyLinked = await checkStudentLinked(chatId);
      if (!isAlreadyLinked) {
        const result = await findAndLinkStudentByNameOrId(text, chatId);
        if (result?.isAlreadyLinkedToOther) {
          await sendTelegramMessage(botToken, chatId, `🔒 <b>القيد موثق بحساب آخر</b>\n\n` + `القيد الخاص بـ (<b>${result.student.name}</b>) مرتبط مسبقاً بحساب تيليجرام آخر.\n` + `في حال واجهت مشكلة، يرجى مراجعة إدارة الكلية.`);
        } else if (result?.isMultiple) {
          const buttons = result.students.map((s)=>{
            const hasFace = Boolean(s.face_embedding && s.face_embedding.length > 0 || s.photo_url);
            const statusText = hasFace ? '✅ البصمة موثقة' : '📸 بانتظار البصمة';
            const cleanStage = (s.stage || '').replace(/المرحلة/g, '').replace(/السنة/g, '').trim();
            const stageText = cleanStage ? `المرحلة ${cleanStage}` : s.stage;
            const secText = s.section ? ` / شعبة (${s.section})` : '';
            return [
              {
                text: `👤 ${s.name} (${statusText}) — ${s.department} • ${stageText}${secText}`,
                callback_data: `pick_student:${s.id}`
              }
            ];
          });
          await sendTelegramMessage(botToken, chatId, `🔍 <b>تم العثور على أكثر من قيد متاح غير مربوط بهذا الاسم:</b>\n` + `يرجى اختيار قيدك الأكاديمي بدقة لتأكيد ربط الحساب:`, {
            inline_keyboard: buttons
          });
        } else if (result) {
          const student = result;
          const hasFace = Boolean(student.face_embedding && student.face_embedding.length > 0 || student.photo_url);
          if (!hasFace) {
            const regUrl = buildStudentRegistrationUrl(student);
            const qrPhotoUrl = `https://quickchart.io/qr?text=${encodeURIComponent(regUrl)}&size=800&margin=4&ecLevel=H&centerImageUrl=${encodeURIComponent('https://nnnnnnn-chi.vercel.app/college-logo.png')}&centerImageSizeRatio=0.22`;
            const cleanStage = (student.stage || '').replace(/المرحلة/g, '').replace(/السنة/g, '').replace(/الدراسية/g, '').trim();
            const stageDisplay = cleanStage ? `المرحلة ${cleanStage}` : student.stage || '';
            const academicSubtitle = [
              student.department || '',
              stageDisplay,
              student.section ? `شعبة (${student.section})` : ''
            ].filter(Boolean).join(' • ');
            const caption = `🏛️ <b>الجامعة الوطنية للعلوم والتكنولوجيا</b>\n` + `📍 <b>الكلية التقنية الهندسية</b>\n` + `━━━━━━━━━━━━━━━━━━━━━\n` + `🎓 <b>بطاقة ورمز تسجيل الطالب</b>\n\n` + `👤 <b>${student.name}</b>\n` + `📚 <b>${academicSubtitle}</b>\n` + `🔢 <code>${student.id}</code>\n` + `━━━━━━━━━━━━━━━━━━━━━\n` + `📸 <b>لتسجيل وتوثيق بصمة وجهك:</b>\n` + `1️⃣ اضغط على الزر أدناه لفتح الكاميرا والتسجيل مباشرة.\n` + `2️⃣ أو امسح الباركود أعلاه بكاميرا هاتف آخر.`;
            await sendTelegramPhoto(botToken, chatId, qrPhotoUrl, caption, {
              inline_keyboard: [
                [
                  {
                    text: '📸 فتح الكاميرا والتسجيل مباشرة',
                    url: regUrl
                  }
                ]
              ]
            });
          } else {
            await sendTelegramMessage(botToken, chatId, `✅ <b>تم ربط حسابك بنجاح</b>\n\n` + `• الطالب: <b>${student.name}</b>\n` + `• القسم: <b>${student.department}</b> — <b>${student.stage}</b>\n` + `بصمة وجهك مسجلة وستصلك إشعارات الحضور تلقائياً.`);
          }
        } else {
          await sendTelegramMessage(botToken, chatId, `⚠️ <b>لم يتم العثور على الاسم</b>\n` + `يرجى كتابة <b>اسمك الرباعي كاملاً</b> أو المعرف الجامعي.`);
        }
      } else {
        await sendTelegramMessage(botToken, chatId, `💡 <b>حسابك مفعل وجاهز</b>\n\n` + `اختر الخدمة المطلوبة أو حمّل التطبيق:\n` + `• <code>/app</code> ➔ تحميل وتثبيت تطبيق محاضراتي (أندرويد وآيفون)\n` + `• <code>/start</code> ➔ نظام الحضور وتسجيل البصمة\n` + `• <code>/id</code> ➔ نسخ المعرف الجامعي فوراً\n` + `• <code>/card</code> ➔ بطاقتي الأكاديمية والقيد`, {
          inline_keyboard: [
            [
              {
                text: '📲 تحميل تطبيق محاضراتي',
                callback_data: 'cmd:app'
              }
            ],
            [
              {
                text: '🔢 نسخ المعرف الجامعي',
                callback_data: 'cmd:id'
              },
              {
                text: '💳 بطاقتي الأكاديمية',
                callback_data: 'cmd:card'
              }
            ],
            [
              {
                text: '💬 الدعم الفني والمساعدة',
                url: 'https://t.me/ii6689'
              }
            ]
          ]
        });
      }
      return new Response(JSON.stringify({
        ok: true
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
    return new Response(JSON.stringify({
      ok: true
    }), {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  } catch (error) {
    console.error('Error handling request:', error);
    return new Response(JSON.stringify({
      error: error.message
    }), {
      status: 500,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  }
});
// ── Helpers ──────────────────────────────────────────────────────────────────
async function sendTelegramMessage(botToken, chatId, text, replyMarkup) {
  const url = `${TELEGRAM_API}${botToken}/sendMessage`;
  const body = {
    chat_id: chatId,
    text: text,
    parse_mode: 'HTML',
    disable_web_page_preview: true
  };
  if (replyMarkup) {
    body.reply_markup = replyMarkup;
  }
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  });
  return await res.json();
}
async function sendTelegramPhoto(botToken, chatId, photoUrl, caption, replyMarkup) {
  const url = `${TELEGRAM_API}${botToken}/sendPhoto`;
  const body = {
    chat_id: chatId,
    photo: photoUrl,
    caption: caption,
    parse_mode: 'HTML'
  };
  if (replyMarkup) {
    body.reply_markup = replyMarkup;
  }
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  });
  return await res.json();
}
async function sendTelegramDocument(botToken, chatId, documentUrlOrId, caption, replyMarkup) {
  const url = `${TELEGRAM_API}${botToken}/sendDocument`;
  const body = {
    chat_id: chatId,
    document: documentUrlOrId,
    parse_mode: 'HTML'
  };
  if (caption) {
    body.caption = caption;
  }
  if (replyMarkup) {
    body.reply_markup = replyMarkup;
  }
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(body)
    });
    return await res.json();
  } catch  {
    return {
      ok: false
    };
  }
}
async function sendTelegramAnimation(botToken, chatId, animationUrlOrId, caption, replyMarkup) {
  const url = `${TELEGRAM_API}${botToken}/sendAnimation`;
  const body = {
    chat_id: chatId,
    animation: animationUrlOrId,
    parse_mode: 'HTML'
  };
  if (caption) {
    body.caption = caption;
  }
  if (replyMarkup) {
    body.reply_markup = replyMarkup;
  }
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(body)
    });
    return await res.json();
  } catch {
    return {
      ok: false
    };
  }
}
async function sendAndroidApkFile(botToken, chatId) {
  const caption = `🤖 <b>تطبيق محاضراتي للأندرويد (APK)</b>\n` +
    `━━━━━━━━━━━━━━━━━━━━━\n` +
    `📦 <b>الإصدار الجديد:</b> v1.0.1\n` +
    `📅 <b>تاريخ التحديث:</b> ${new Date().toLocaleDateString('ar-EG')}\n` +
    `━━━━━━━━━━━━━━━━━━━━━\n` +
    `اضغط على الملف أعلاه لتنزيله ثم اختر <b>تثبيت (Install)</b>.`;
  await sendTelegramDocument(botToken, chatId, APK_FILE_ID, caption);
}
async function sendAndroidInstallGuide(botToken, chatId) {
  await sendAndroidApkFile(botToken, chatId);
}
async function sendIosInstallGuide(botToken, chatId) {
  const caption = `🍏 <b>تثبيت وتحديث تطبيق محاضراتي للآيفون (iOS)</b>\n` +
    `━━━━━━━━━━━━━━━━━━━━━\n` +
    `📦 <b>الإصدار الجديد:</b> v1.0.1 (أحدث نسخة)\n` +
    `━━━━━━━━━━━━━━━━━━━━━\n` +
    `1️⃣ اضغط على الزر أدناه ثم اختر <b>(سماح / Allow)</b>.\n` +
    `2️⃣ افتح <b>الإعدادات (Settings)</b> ⚙️ على هاتفك.\n` +
    `3️⃣ اضغط على <b>(تم تنزيل ملف التعريف)</b> في الأعلى ثم <b>تثبيت (Install)</b>.\n` +
    `4️⃣ أدخل رمز قفل الشاشة (Passcode) الخاص بهاتفك لتأكيد التثبيت.\n\n` +
    `✨ <i>ملاحظة: إذا كان التطبيق مثبتاً لديك مسبقاً، فسيتم تحديثه تلقائياً بمجرد فتحه!</i>`;
  const replyMarkup = {
    inline_keyboard: [
      [
        {
          text: '🚀 تنزيل ملف التعريف وتثبيت التطبيق',
          url: 'https://mohadarati.vercel.app/api/mobileconfig'
        }
      ]
    ]
  };
  const animRes = await sendTelegramAnimation(botToken, chatId, IOS_GUIDE_FILE_ID, caption, replyMarkup);
  if (!animRes || !animRes.ok) {
    await sendTelegramMessage(botToken, chatId, caption, replyMarkup);
  }
}
async function sendAppOverviewMenu(botToken, chatId) {
  const appMsg = `📲 <b>تطبيق محاضراتي</b>\n` +
    `━━━━━━━━━━━━━━━━━━━━━\n` +
    `اختر طريقة التثبيت المناسبة لجهازك:`;
  await sendTelegramMessage(botToken, chatId, appMsg, {
    inline_keyboard: [
      [
        {
          text: '🍏 تثبيت تطبيق الآيفون (iOS)',
          callback_data: 'cmd:ios'
        }
      ],
      [
        {
          text: '🤖 تحميل تطبيق الأندرويد (APK)',
          callback_data: 'cmd:apk'
        }
      ],
      [
        {
          text: '🌐 فتح عبر المتصفح (لجميع الأجهزة)',
          url: 'https://mohadarati.vercel.app'
        }
      ]
    ]
  });
}
async function editTelegramMessageText(botToken, chatId, messageId, text, replyMarkup) {
  const url = `${TELEGRAM_API}${botToken}/editMessageText`;
  const body = {
    chat_id: chatId,
    message_id: messageId,
    text: text,
    parse_mode: 'HTML',
    disable_web_page_preview: true
  };
  if (replyMarkup) {
    body.reply_markup = replyMarkup;
  }
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(body)
    });
    return await res.json();
  } catch  {
    return {
      ok: false
    };
  }
}
async function answerCallbackQuery(botToken, callbackQueryId) {
  try {
    await fetch(`${TELEGRAM_API}${botToken}/answerCallbackQuery`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        callback_query_id: callbackQueryId
      })
    });
  } catch  {}
}
function normalizeStageName(str = '') {
  const s = str.trim();
  if (s.includes('رابع') || s.includes('4') || s.includes('fourth')) return 'رابعة';
  if (s.includes('ثالث') || s.includes('3') || s.includes('third')) return 'ثالثة';
  if (s.includes('ثاني') || s.includes('2') || s.includes('second')) return 'ثانية';
  if (s.includes('اول') || s.includes('أول') || s.includes('1') || s.includes('first')) return 'أولى';
  return s;
}
function normalizeDeptName(str = '') {
  const s = str.trim();
  if (s.includes('أجهزة') || s.includes('طبية') || s.includes('med')) return 'طبية';
  if (s.includes('حاسوب') || s.includes('كمبيوتر') || s.includes('comp')) return 'حاسوب';
  if (s.includes('سيبراني') || s.includes('أمن') || s.includes('cyber')) return 'أمن';
  return s;
}
async function resolveDeptId(supabase, studentDept = '') {
  const { data: depts } = await supabase.from('departments').select('id, name');
  if (!depts || depts.length === 0) return null;
  const exact = depts.find((d)=>d.name.trim() === studentDept.trim() || d.id === studentDept.trim());
  if (exact) return exact.id;
  const normTarget = normalizeDeptName(studentDept);
  const matched = depts.find((d)=>normalizeDeptName(d.name) === normTarget || normalizeDeptName(d.id) === normTarget);
  if (matched) return matched.id;
  return depts[0]?.id || null;
}
async function resolveStageId(supabase, deptId, studentStage = '') {
  const { data: stages } = await supabase.from('stages').select('id, name').eq('department_id', deptId);
  if (!stages || stages.length === 0) return null;
  const exact = stages.find((st)=>st.name.trim() === studentStage.trim() || st.id === studentStage.trim());
  if (exact) return exact.id;
  const normTarget = normalizeStageName(studentStage);
  const matched = stages.find((st)=>normalizeStageName(st.name) === normTarget || normalizeStageName(st.id) === normTarget);
  if (matched) return matched.id;
  return stages[0]?.id || null;
}
function generateSecureRegistrationToken(student) {
  const payload = {
    id: student.id,
    name: student.name,
    department: student.department,
    stage: student.stage,
    section: student.section || '',
    chat_id: student.telegram_chat_id,
    exp: Date.now() + 24 * 60 * 60 * 1000
  };
  return btoa(unescape(encodeURIComponent(JSON.stringify(payload))));
}
function buildStudentRegistrationUrl(student) {
  const regToken = generateSecureRegistrationToken(student);
  const base = 'https://nnnnnnn-chi.vercel.app/#/verify';
  const query = new URLSearchParams({
    id: student.id || '',
    name: student.name || '',
    dept: student.department || '',
    stage: student.stage || '',
    sec: student.section || '',
    auth: regToken
  });
  return `${base}?${query.toString()}`;
}
async function checkStudentLinked(chatId) {
  const supabase = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');
  const { data } = await supabase.from('students').select('id').eq('telegram_chat_id', chatId).limit(1);
  return Boolean(data && data.length > 0);
}
async function getStudentByChatId(chatId) {
  const supabase = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');
  const { data } = await supabase.from('students').select('*').eq('telegram_chat_id', chatId).maybeSingle();
  return data;
}
function normalizeArabic(str) {
  return str.replace(/[إأآا]/g, 'ا').replace(/ى/g, 'ي').replace(/ة/g, 'ه').replace(/[\u064B-\u065F]/g, '').replace(/\s+/g, ' ').trim();
}
async function findAndLinkStudentByNameOrId(query, chatId) {
  const supabase = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');
  const cleanQ = query.replace(/\s+/g, ' ').trim();
  // 1. By exact ID
  const { data: byId } = await supabase.from('students').select('*').eq('id', cleanQ).maybeSingle();
  if (byId) {
    if (byId.telegram_chat_id && byId.telegram_chat_id !== chatId) {
      return {
        isAlreadyLinkedToOther: true,
        student: byId
      };
    }
    const hasFace = Boolean(byId.face_embedding && byId.face_embedding.length > 0 || byId.photo_url);
    if (hasFace) {
      await supabase.from('students').update({
        telegram_chat_id: chatId
      }).eq('id', byId.id);
    }
    return byId;
  }
  // 2. By Exact Name — Match EXACTLY as registered in system (NO substring wildcards)
  const { data: exactMatches } = await supabase.from('students').select('*').ilike('name', cleanQ).or(`telegram_chat_id.is.null,telegram_chat_id.eq.${chatId}`);
  let validMatches = exactMatches || [];
  // If no direct ilike match, try Arabic-normalized exact match on full name
  if (validMatches.length === 0) {
    const normQ = normalizeArabic(cleanQ);
    const { data: allUnlinked } = await supabase.from('students').select('*').or(`telegram_chat_id.is.null,telegram_chat_id.eq.${chatId}`).limit(300);
    if (allUnlinked) {
      validMatches = allUnlinked.filter((s)=>normalizeArabic(s.name || '') === normQ);
    }
  }
  if (validMatches.length === 1) {
    const student = validMatches[0];
    const hasFace = Boolean(student.face_embedding && student.face_embedding.length > 0 || student.photo_url);
    if (hasFace) {
      await supabase.from('students').update({
        telegram_chat_id: chatId
      }).eq('id', student.id);
    }
    return student;
  }
  if (validMatches.length > 1) {
    return {
      isMultiple: true,
      students: validMatches
    };
  }
  // If no unlinked students found, check if an exact-match student is already claimed by another telegram account
  const { data: alreadyClaimed } = await supabase.from('students').select('*').ilike('name', cleanQ).not('telegram_chat_id', 'is', null).limit(1);
  if (alreadyClaimed && alreadyClaimed.length > 0) {
    return {
      isAlreadyLinkedToOther: true,
      student: alreadyClaimed[0]
    };
  }
  return null;
}
/**
 * Builds dynamic inline keyboard for the student based only on the days they have lectures!
 */ async function getStudentScheduleInlineKeyboard(chatId) {
  const supabase = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');
  const { data: student } = await supabase.from('students').select('department, stage, section').eq('telegram_chat_id', chatId).maybeSingle();
  if (!student) return undefined;
  const deptId = await resolveDeptId(supabase, student.department || '');
  if (!deptId) return undefined;
  const stageId = await resolveStageId(supabase, deptId, student.stage || '');
  if (!stageId) return undefined;
  const { data: scheds } = await supabase.from('weekly_schedules').select('day_of_week, section').eq('department_id', deptId).eq('stage_id', stageId);
  if (!scheds || scheds.length === 0) return undefined;
  // Filter schedules matching student section
  const validScheds = scheds.filter((s)=>!s.section || !student.section || s.section === student.section);
  const distinctDaysOrder = [
    'saturday',
    'sunday',
    'monday',
    'tuesday',
    'wednesday',
    'thursday'
  ];
  const presentDays = distinctDaysOrder.filter((d)=>validScheds.some((s)=>s.day_of_week === d));
  if (presentDays.length === 0) return undefined;
  const buttonsRow = presentDays.map((d)=>({
      text: `📅 ${dayArabic[d]}`,
      callback_data: `day:${d}`
    }));
  // Chunk buttons into rows of 3
  const keyboard = [];
  for(let i = 0; i < buttonsRow.length; i += 3){
    keyboard.push(buttonsRow.slice(i, i + 3));
  }
  // Add Today quick button
  keyboard.push([
    {
      text: '🌟 جدول ومحاضرات اليوم',
      callback_data: 'action:today'
    }
  ]);
  return {
    inline_keyboard: keyboard
  };
}
async function getStudentScheduleForDay(chatId, targetDay) {
  const supabase = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');
  const { data: student } = await supabase.from('students').select('*').eq('telegram_chat_id', chatId).maybeSingle();
  if (!student) {
    return '⚠️ يرجى ربط حسابك أولاً بإرسال اسمك الرباعي.';
  }
  const dayNameAr = dayArabic[targetDay] || targetDay;
  // Fetch schedules
  let scheduledLessons = [];
  try {
    const deptId = await resolveDeptId(supabase, student.department || '');
    if (deptId) {
      const stageId = await resolveStageId(supabase, deptId, student.stage || '');
      if (stageId) {
        const { data: scheds } = await supabase.from('weekly_schedules').select('*').eq('department_id', deptId).eq('stage_id', stageId).eq('day_of_week', targetDay);
        if (scheds) {
          scheduledLessons = scheds.filter((s)=>!s.section || !student.section || s.section === student.section);
        }
      }
    }
  } catch  {}
  let responseText = `📅 <b>جدول يوم (${dayNameAr})</b> — ${student.department} (${student.stage}${student.section ? ` / ${student.section}` : ''}):\n` + `━━━━━━━━━━━━━━━━━━━━━\n\n`;
  if (scheduledLessons.length > 0) {
    scheduledLessons.forEach((item)=>{
      const typeBadge = item.subject_type === 'عملي' ? '🔬 [عملي]' : '📖 [نظري]';
      responseText += `• <b>${item.start_time} - ${item.end_time}</b> | <b>${item.subject_name}</b> ${typeBadge}\n`;
      if (item.professor_name || item.hall) {
        const details = [
          item.professor_name,
          item.hall
        ].filter(Boolean).join(' • ');
        responseText += `  📍 <i>${details}</i>\n`;
      }
      responseText += `\n`;
    });
  } else {
    responseText += `💡 لا توجد محاضرات مجدولة لهذا اليوم.\n\n`;
  }
  responseText += `🏛️ <i>الجامعة الوطنية للعلوم والتكنولوجيا — NUST</i>`;
  return responseText;
}
async function getStudentTodaySchedule(chatId) {
  const supabase = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');
  const { data: student } = await supabase.from('students').select('*').eq('telegram_chat_id', chatId).maybeSingle();
  if (!student) {
    return '⚠️ يرجى ربط حسابك أولاً بإرسال اسمك الرباعي.';
  }
  const now = new Date();
  const baghdadDate = new Date(now.toLocaleString('en-US', {
    timeZone: 'Asia/Baghdad'
  }));
  const daysMap = [
    'sunday',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday'
  ];
  const currentDayId = daysMap[baghdadDate.getDay()];
  const currentDayNameAr = dayArabic[currentDayId] || 'اليوم';
  const todayStr = baghdadDate.toISOString().slice(0, 10);
  // Today attendance records
  let todayRecords = [];
  try {
    const { data: allRecs } = await supabase.from('attendance_records').select('subject_name').eq('student_id', student.id).eq('date', todayStr);
    if (allRecs) todayRecords = allRecs;
  } catch  {}
  const attendedSubjects = new Set(todayRecords.map((r)=>r.subject_name?.trim().toLowerCase()).filter(Boolean));
  // Fetch schedule
  let scheduledLessons = [];
  try {
    const deptId = await resolveDeptId(supabase, student.department || '');
    if (deptId) {
      const stageId = await resolveStageId(supabase, deptId, student.stage || '');
      if (stageId) {
        const { data: scheds } = await supabase.from('weekly_schedules').select('*').eq('department_id', deptId).eq('stage_id', stageId).eq('day_of_week', currentDayId);
        if (scheds) {
          scheduledLessons = scheds.filter((s)=>!s.section || !student.section || s.section === student.section);
        }
      }
    }
  } catch  {}
  let responseText = `📅 <b>محاضرات اليوم (${currentDayNameAr})</b> — ${todayStr}\n` + `👤 <b>${student.name}</b> (${student.department} - ${student.stage}${student.section ? ` / ${student.section}` : ''})\n` + `━━━━━━━━━━━━━━━━━━━━━\n\n`;
  if (scheduledLessons.length > 0) {
    scheduledLessons.forEach((item)=>{
      const isAttended = attendedSubjects.has(item.subject_name?.trim().toLowerCase());
      const typeBadge = item.subject_type === 'عملي' ? '🔬 [عملي]' : '📖 [نظري]';
      const statusIcon = isAttended ? '✅ تم الحضور' : '⏳ لم يُسجل';
      responseText += `• <b>${item.start_time} - ${item.end_time}</b> | <b>${item.subject_name}</b> ${typeBadge}\n`;
      if (item.professor_name || item.hall) {
        const details = [
          item.professor_name,
          item.hall
        ].filter(Boolean).join(' • ');
        responseText += `  📍 <i>${details}</i>\n`;
      }
      responseText += `  🔹 <b>الحالة:</b> ${statusIcon}\n\n`;
    });
  } else {
    if (currentDayId === 'friday') {
      responseText += `🌴 <b>عطلة نهاية الأسبوع (يوم الجمعة)</b> — لا توجد محاضرات.\n\n`;
    } else {
      responseText += `💡 لا توجد محاضرات مجدولة لهذا اليوم.\n\n`;
    }
  }
  responseText += `🏛️ <i>الجامعة الوطنية للعلوم والتكنولوجيا — NUST</i>`;
  return responseText;
}
async function getStudentProfile(chatId) {
  const supabase = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');
  const { data: studentsList } = await supabase.from('students').select('id, name, department, stage, section, face_embedding, photo_url').eq('telegram_chat_id', chatId).order('registered_at', {
    ascending: false
  });
  const student = studentsList && studentsList.length > 0 ? studentsList[0] : null;
  if (!student) {
    return `⚠️ <b>الحساب غير مرتبط برقم التيليجرام هذا حتى الآن.</b>\n\nيرجى إرسال <b>اسمك الرباعي كاملاً</b> هنا في المحادثة للبحث عن قيدك وربطه فوراً.`;
  }
  const hasFace = Boolean(student.face_embedding && student.face_embedding.length > 0 || student.photo_url);
  const faceStatus = hasFace ? '✅ موثقة في النظام' : '⚠️ بانتظار التوثيق';
  return `💳 <b>بطاقة وقيد الطالب الأكاديمي:</b>\n` + `━━━━━━━━━━━━━━━━━━━━━\n` + `👤 الاسم: <b>${student.name}</b> 🎓\n` + `📚 القسم: <b>${student.department}</b>\n` + `🏛️ المرحلة: <b>${student.stage}</b>${student.section ? ` (${student.section})` : ''}\n` + `🔐 بصمة الوجه: <b>${faceStatus}</b>\n` + `━━━━━━━━━━━━━━━━━━━━━\n` + `🔢 المعرف الجامعي:\n<code>${student.id}</code>\n` + `━━━━━━━━━━━━━━━━━━━━━\n` + `💡 <i>انقر على المعرف لنسخه بنقرة واحدة والصقه في تطبيق محاضراتي.</i>\n\n` + `🏛️ <i>الجامعة الوطنية للعلوم والتكنولوجيا</i>`;
}
async function getStudentIdOnly(chatId) {
  const supabase = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');
  const { data: studentsList } = await supabase.from('students').select('id').eq('telegram_chat_id', chatId).order('registered_at', {
    ascending: false
  });
  const student = studentsList && studentsList.length > 0 ? studentsList[0] : null;
  if (!student) {
    return `⚠️ <b>الحساب غير مرتبط برقم التيليجرام هذا حتى الآن.</b>\n\nيرجى كتابة وإرسال <b>اسمك الرباعي كاملاً</b> للبحث عن قيدك وربطه فوراً.`;
  }
  // إرسال كود المعرف مجرداً تماماً بدون أي نص إضافي
  return `<code>${student.id}</code>`;
}
