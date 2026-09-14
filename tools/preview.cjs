// Local preview server for the Flutter web build. No external packages required.
const http = require('http');
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '../build/web');
const mime = {'.html':'text/html', '.js':'application/javascript', '.mjs':'application/javascript', '.json':'application/json', '.png':'image/png', '.woff2':'font/woff2', '.ttf':'font/ttf', '.wasm':'application/wasm'};
http.createServer((request, response) => {
  let file;
  try { file = path.resolve(root, '.' + decodeURIComponent(new URL(request.url, 'http://localhost').pathname)); }
  catch (_) { response.writeHead(400); response.end(); return; }
  if (file !== root && !file.startsWith(root + path.sep)) { response.writeHead(403); response.end(); return; }
  if (file === root || fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
  fs.readFile(file, (error, data) => {
    if (error) { response.writeHead(404); response.end('Not found'); return; }
    response.writeHead(200, {'Content-Type':mime[path.extname(file)] || 'application/octet-stream'});
    response.end(data);
  });
}).listen(8080, '127.0.0.1', () => console.log('SignBridge: http://127.0.0.1:8080'));
