const BOT_TOKEN = '8816281220:AAFAduddee7N8mD-UNgQIgfQ1yiFaGbdHU8';

module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', '*');
  res.setHeader('Content-Disposition', 'inline');

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
      targetUrl = decodeURIComponent(url);
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
