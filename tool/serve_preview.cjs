// Preview local do build Flutter e da mesma função usada na Vercel.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const handler = require('../api/concursos.js');
const config = require('../vercel.json');
const root = path.resolve(__dirname, '../build/web');
const types = {'.html':'text/html','.js':'text/javascript','.json':'application/json',
  '.wasm':'application/wasm','.png':'image/png','.ttf':'font/ttf','.otf':'font/otf'};
http.createServer(async (req, res) => {
  for (const h of config.headers[0].headers) res.setHeader(h.key, h.value);
  const url = new URL(req.url, 'http://localhost');
  if (url.pathname === '/api/concursos') {
    req.query = Object.fromEntries(url.searchParams);
    res.status = code => {res.statusCode=code; return res;};
    res.json = value => {res.setHeader('Content-Type','application/json');res.end(JSON.stringify(value));};
    return handler(req,res);
  }
  let file = path.resolve(root, '.' + decodeURIComponent(url.pathname));
  if (!file.startsWith(root + path.sep) && file !== root) {res.writeHead(403); return res.end();}
  if (file === root || !fs.existsSync(file)) file = path.join(root, 'index.html');
  if (!fs.statSync(file).isFile()) {res.writeHead(404);return res.end();}
  res.setHeader('Content-Type', types[path.extname(file)] || 'application/octet-stream');
  fs.createReadStream(file).pipe(res);
}).listen(Number(process.argv[2] || 4180), '127.0.0.1', () => console.log('Preview: http://127.0.0.1:' + (process.argv[2] || 4180)));
