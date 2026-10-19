const BOT_TOKEN = process.env.LECTURES_BOT_TOKEN || Buffer.from('ODgxNjI4MTIyMDpBQUZBZHVkZGVlN044bUQtVU5nUUlnZlExeWlGYUdiZEhVOA==', 'base64').toString('utf8');

// نطاقات آمنة ومصرح لها بالمرور حصراً لمنع ثغرات Server-Side Request Forgery (SSRF)
const STRICT_EXACT_DOMAINS = new Set([
  'api.telegram.org',
  'quickchart.io',
  'mrubdzgcjofjwirkdfwo.supabase.co',
  'rlupqsmqwvidmwrvqrcc.supabase.co',
  'mohadarati.vercel.app',
  'mohadarati-app.vercel.app',
]);

function isSafeUrl(rawUrl) {
  try {
    const parsed = new URL(rawUrl);
    if (parsed.protocol !== 'https:') return false;
    const hostname = parsed.hostname.toLowerCase();

    // حظر عناوين الشبكة المحلية والـ Metadata السحابية منعاً باتاً
    if (
      hostname === 'localhost' ||
      hostname.startsWith('127.') ||
      hostname.startsWith('192.168.') ||
      hostname.startsWith('10.') ||
      hostname.startsWith('172.16.') ||
      hostname.startsWith('172.17.') ||
      hostname.startsWith('172.18.') ||
      hostname.startsWith('172.19.') ||
      hostname.startsWith('172.20.') ||
      hostname.startsWith('172.21.') ||
      hostname.startsWith('172.22.') ||
      hostname.startsWith('172.23.') ||
      hostname.startsWith('172.24.') ||
      hostname.startsWith('172.25.') ||
      hostname.startsWith('172.26.') ||
      hostname.startsWith('172.27.') ||
      hostname.startsWith('172.28.') ||
      hostname.startsWith('172.29.') ||
      hostname.startsWith('172.30.') ||
      hostname.startsWith('172.31.') ||
      hostname === '169.254.169.254' ||
      hostname === '0.0.0.0' ||
      hostname.endsWith('.internal') ||
      hostname.endsWith('.local')
    ) {
      return false;
    }

    if (STRICT_EXACT_DOMAINS.has(hostname)) return true;
    if (hostname.endsWith('.supabase.co') && (hostname.includes('mrubdzgcjofjwirkdfwo') || hostname.includes('rlupqsmqwvidmwrvqrcc'))) return true;
    if (hostname.endsWith('.vercel.app') && (hostname.includes('mohadarati'))) return true;

    return false;
  } catch {
    return false;
  }
}

async function safeFetch(targetUrl) {
  const signal = AbortSignal.timeout(15000);
  let res = await fetch(targetUrl, { redirect: 'manual', signal });

  // التحقق الصارم من التوجيهات (301, 302, 307, 308) لمنع الالتفاف نحو شبكات داخلية
  if (res.status >= 300 && res.status < 400) {
    const loc = res.headers.get('location');
    if (!loc) throw new Error('Redirect without location header');
    const redirectUrl = new URL(loc, targetUrl).toString();
    if (!isSafeUrl(redirectUrl)) {
      throw new Error('Redirect to unauthorized destination blocked');
    }
    res = await fetch(redirectUrl, { redirect: 'manual', signal });
  }
  return res;
}

module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', '*');
  res.setHeader('Content-Disposition', 'inline');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Content-Security-Policy', "default-src 'none'; sandbox");

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method Not Allowed' });
  }

  const { url, file_id } = req.query;
  if (!url && !file_id) {
    return res.status(400).json({ error: 'Missing url or file_id parameter' });
  }

  try {
    let targetUrl = '';

    if (file_id) {
      const getFileRes = await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/getFile?file_id=${encodeURIComponent(file_id)}`, {
        signal: AbortSignal.timeout(10000),
      });
      if (getFileRes.ok) {
        const getFileData = await getFileRes.json();
        const filePath = getFileData.result?.file_path;
        if (filePath) {
          targetUrl = `https://api.telegram.org/file/bot${BOT_TOKEN}/${filePath}`;
        }
      }
    }

    if (!targetUrl && url) {
      const decoded = decodeURIComponent(url);
      if (!isSafeUrl(decoded)) {
        return res.status(403).json({ error: 'Forbidden: Target URL domain is not in the safe allowlist' });
      }
      targetUrl = decoded;
    }

    if (!targetUrl) {
      return res.status(404).json({ error: 'Could not resolve file target' });
    }

    let response = await safeFetch(targetUrl);

    // إذا انتهت صلاحية الرابط السحابي المؤقت، نحاول التحديث عبر file_id إن وجد
    if (!response.ok && file_id) {
      const getFileRes = await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/getFile?file_id=${encodeURIComponent(file_id)}`, {
        signal: AbortSignal.timeout(10000),
      });
      if (getFileRes.ok) {
        const getFileData = await getFileRes.json();
        const filePath = getFileData.result?.file_path;
        if (filePath) {
          targetUrl = `https://api.telegram.org/file/bot${BOT_TOKEN}/${filePath}`;
          response = await safeFetch(targetUrl);
        }
      }
    }

    if (!response.ok) {
      return res.status(response.status).send(`Upstream error: ${response.statusText}`);
    }

    let contentType = response.headers.get('content-type') || '';
    const lower = targetUrl.toLowerCase();
    if (!contentType || contentType.includes('octet-stream') || contentType.includes('text/plain')) {
      if (lower.endsWith('.png') || lower.includes('.png')) contentType = 'image/png';
      else if (lower.endsWith('.webp') || lower.includes('.webp')) contentType = 'image/webp';
      else if (lower.endsWith('.gif') || lower.includes('.gif')) contentType = 'image/gif';
      else if (lower.endsWith('.pdf') || lower.includes('.pdf')) contentType = 'application/pdf';
      else if (lower.includes('photos/') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.includes('.jpg')) contentType = 'image/jpeg';
      else contentType = 'image/jpeg';
    }

    const upstreamLength = parseInt(response.headers.get('content-length') || '0', 10);
    if (upstreamLength > 20 * 1024 * 1024) {
      return res.status(413).json({ error: 'Payload too large (max 20MB)' });
    }

    const arrayBuffer = await response.arrayBuffer();
    if (arrayBuffer.byteLength > 20 * 1024 * 1024) {
      return res.status(413).json({ error: 'Payload too large (max 20MB)' });
    }
    const buffer = Buffer.from(arrayBuffer);

    res.setHeader('Content-Type', contentType);
    res.setHeader('Cache-Control', 'public, max-age=604800, immutable');
    res.setHeader('Content-Length', buffer.length.toString());
    return res.status(200).send(buffer);
  } catch (error) {
    console.error('[-] Proxy Error:', error.message);
    return res.status(500).json({ error: 'Internal proxy processing error' });
  }
};
