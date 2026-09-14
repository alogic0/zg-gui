import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';
import { pathToFileURL } from 'node:url';

export async function serve({ directory, port = 0 }) {
  const base = resolve(directory);
  const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.wasm': 'application/wasm' };
  const server = createServer(async (request, response) => {
    try {
      const path = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
      const file = resolve(base, `.${path === '/' ? '/index.html' : path}`);
      if (!file.startsWith(base + sep)) { response.writeHead(403).end(); return; }
      const body = await readFile(file);
      response.writeHead(200, { 'Content-Type': types[extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
      response.end(body);
    } catch { response.writeHead(404).end('Not found'); }
  });
  await new Promise((accept, reject) => { server.once('error', reject); server.listen(port, '127.0.0.1', accept); });
  return { url: `http://127.0.0.1:${server.address().port}`, close: () => new Promise((accept, reject) => {
    server.close(error => error ? reject(error) : accept());
    server.closeAllConnections();
  }) };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const server = await serve({ directory: process.argv[2] || 'zig-out/web', port: Number(process.argv[3] || 4180) });
  console.log(`zg-gui example: ${server.url}`);
  for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, async () => { await server.close(); process.exit(0); });
}
