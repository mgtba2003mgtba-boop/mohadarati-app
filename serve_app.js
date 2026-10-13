const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 8080;
const HOST = '0.0.0.0';
const WEB_DIR = path.join(__dirname, 'build', 'web');

const MIME_TYPES = {
  '.html': 'text/html; charset=UTF-8',
  '.js': 'application/javascript; charset=UTF-8',
  '.mjs': 'application/javascript; charset=UTF-8',
  '.wasm': 'application/wasm',
  '.json': 'application/json',
  '.css': 'text/css',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
};

const server = http.createServer((req, res) => {
  const clientIp = req.socket.remoteAddress || 'Unknown';
  const urlPath = req.url.split('?')[0];
  console.log(`[${new Date().toLocaleTimeString()}] ${req.method} ${urlPath} from ${clientIp}`);

  // إعداد ترويسات CORS وحماية الاتصال
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', '*');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  // توجيه مسارات /api/ مباشرة لسيرفر تيليجرام على بورت 8050 لتوحيد المنفذ ومنع أخطاء CORS
  if (urlPath.startsWith('/api/')) {
    const proxyReq = http.request({
      hostname: '127.0.0.1',
      port: 8050,
      path: req.url,
      method: req.method,
      headers: { ...req.headers, host: '127.0.0.1:8050' },
    }, (proxyRes) => {
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res);
    });
    proxyReq.on('error', (err) => {
      res.writeHead(502, { 'Content-Type': 'text/plain' });
      res.end('Bad Gateway: ' + err.message);
    });
    req.pipe(proxyReq);
    return;
  }

  if (urlPath === '/client-log') {
    console.error(`\x1b[31m[CLIENT REPORT] ${req.url}\x1b[0m`);
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('ok');
    return;
  }

  let filePath = path.join(WEB_DIR, urlPath === '/' ? 'index.html' : urlPath);

  // إذا لم يكن الملف موجوداً، التوجيه إلى index.html (تطبيق SPA)
  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    filePath = path.join(WEB_DIR, 'index.html');
  }

  const ext = path.extname(filePath).toLowerCase();
  const contentType = MIME_TYPES[ext] || 'application/octet-stream';
  const isHtml = ext === '.html' || filePath.endsWith('index.html');
  const cacheControl = isHtml 
    ? 'no-cache, no-store, must-revalidate' 
    : 'public, max-age=31536000, immutable';

  fs.readFile(filePath, (err, content) => {
    if (err) {
      res.writeHead(500, { 'Content-Type': 'text/plain; charset=UTF-8' });
      res.end(`Internal Server Error: ${err.message}`);
      return;
    }

    res.writeHead(200, {
      'Content-Type': contentType,
      'Cache-Control': cacheControl,
    });
    res.end(content);
  });
});

server.listen(PORT, HOST, () => {
  console.log(`\n======================================================`);
  console.log(`🚀 سيرفر تطبيق الطالب الأكاديمي يعمل الآن على الشبكة المحلية:`);
  console.log(`   - من المتصفح محلياً:    http://localhost:${PORT}`);
  console.log(`   - من الهاتف عبر Wi-Fi:   http://192.168.100.25:${PORT}`);
  console.log(`======================================================\n`);
});
