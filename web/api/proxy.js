const BOT_TOKEN = process.env.LECTURES_BOT_TOKEN || Buffer.from('ODgxNjI4MTIyMDpBQUZBZHVkZGVlN044bUQtVU5nUUlnZlExeWlGYUdiZEhVOA==', 'base64').toString('utf8');

// نطاقات آمنة ومصرح لها بالمرور حصراً لمنع ثغرات Server-Side Request Forgery (SSRF)
const ALLOWED_DOMAINS = [
  'api.telegram.org',
  'mrubdzgcjofjwirkdfwo.supabase.co',
  'rlupqsmqwvidmwrvqrcc.supabase.co',
  'mohadarati.vercel.app',
  'mohadarati-app.vercel.app',
  'quickchart.io',
];

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
      hostname === '169.254.169.254' ||
      hostname.endsWith('.internal') ||
      hostname.endsWith('.local')
    ) {
      return false;
    }
    return ALLOWED_DOMAINS.some(d => hostname === d || hostname.endsWith('.' + d));
  } catch {
    return false;
  }
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

  const { url, file_id } = req.query;
  if (!url && !file_id) {
    return res.status(400).json({ error: 'Missing url or file_id parameter' });
  }

  try {
    let targetUrl = '';

    if (file_id) {
      const getFileRes = await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/getFile?file_id=${encodeURIComponent(file_id)}`);
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

    let response = await fetch(targetUrl);

    // إذا انتهت صلاحية الرابط السحابي المؤقت، نحاول التحديث عبر file_id إن وجد
    if (!response.ok && file_id) {
      const getFileRes = await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/getFile?file_id=${encodeURIComponent(file_id)}`);
      if (getFileRes.ok) {
        const getFileData = await getFileRes.json();
        const filePath = getFileData.result?.file_path;
        if (filePath) {
          targetUrl = `https://api.telegram.org/file/bot${BOT_TOKEN}/${filePath}`;
          response = await fetch(targetUrl);
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

    const arrayBuffer = await response.arrayBuffer();
    const buffer = Buffer.from(arrayBuffer);

    res.setHeader('Content-Type', contentType);
    res.setHeader('Cache-Control', 'public, max-age=604800, immutable');
    res.setHeader('Content-Length', buffer.length.toString());
    return res.status(200).send(buffer);
  } catch (error) {
    return res.status(500).json({ error: error.message });
  }
};
