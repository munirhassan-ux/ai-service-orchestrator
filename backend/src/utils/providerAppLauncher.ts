import * as http from "http";
import * as net from "net";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { exec } from "child_process";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Pre-built Flutter provider web app — build once with:
//   cd frontend && flutter build web -t lib/main_provider.dart -o build/web_provider
const BUILD_DIR = path.join(__dirname, "../../../frontend/build/web_provider");

const _servers = new Map<string, { port: number; server: http.Server }>();
let _nextPort = 57654;

function _mime(ext: string): string {
  const map: Record<string, string> = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript",
    ".mjs": "application/javascript",
    ".css": "text/css",
    ".json": "application/json",
    ".wasm": "application/wasm",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".svg": "image/svg+xml",
    ".ico": "image/x-icon",
    ".ttf": "font/ttf",
    ".woff": "font/woff",
    ".woff2": "font/woff2",
  };
  return map[ext] ?? "application/octet-stream";
}

function _checkPort(port: number): Promise<boolean> {
  return new Promise(resolve => {
    const sock = net.createConnection({ port, host: "127.0.0.1" });
    const done = (v: boolean) => { try { sock.destroy(); } catch {} resolve(v); };
    sock.on("connect", () => done(true));
    sock.on("error",   () => done(false));
    setTimeout(() => done(false), 300);
  });
}

async function _freePort(): Promise<number> {
  for (let p = _nextPort; p < _nextPort + 100; p++) {
    if (!(await _checkPort(p))) return p;
  }
  return _nextPort;
}

function _startServer(port: number): Promise<http.Server> {
  return new Promise((resolve, reject) => {
    const server = http.createServer((req, res) => {
      // Strip query string, prevent path traversal
      const urlPath = (req.url ?? "/").split("?")[0].replace(/\.\./g, "");
      const filePath = path.join(BUILD_DIR, urlPath === "/" ? "index.html" : urlPath);

      if (!filePath.startsWith(BUILD_DIR)) {
        res.writeHead(403); res.end(); return;
      }

      fs.readFile(filePath, (err, data) => {
        if (err) {
          // SPA fallback → index.html for any unknown route
          fs.readFile(path.join(BUILD_DIR, "index.html"), (_e, d) => {
            if (!d) { res.writeHead(404); res.end("Not found"); return; }
            res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
            res.end(d);
          });
          return;
        }
        res.writeHead(200, { "Content-Type": _mime(path.extname(filePath)) });
        res.end(data);
      });
    });

    server.listen(port, "127.0.0.1", () => resolve(server));
    server.on("error", reject);
  });
}

const C = { reset: "\x1b[0m", bold: "\x1b[1m", green: "\x1b[32m", cyan: "\x1b[36m", yellow: "\x1b[33m" };

export async function launchProviderApp(providerName: string, bookingId: string, providerId?: string): Promise<void> {
  const idParam = providerId ? `&providerId=${encodeURIComponent(providerId)}` : "";

  // Guard: build must exist
  if (!fs.existsSync(path.join(BUILD_DIR, "index.html"))) {
    console.warn(`${C.yellow}${C.bold}[ProviderApp] Pre-built app not found at ${BUILD_DIR}`);
    console.warn(`  Run once before demoing:`);
    console.warn(`  cd frontend && flutter build web -t lib/main_provider.dart -o build/web_provider${C.reset}`);
    exec(`open "http://localhost:57654?provider=${encodeURIComponent(providerName)}${idParam}"`, () => {});
    return;
  }

  const port = await _freePort();
  _nextPort = port + 1;

  console.log(`\n${C.cyan}${C.bold}[ProviderApp] Launching for ${providerName} on port ${port}...${C.reset}`);

  try {
    const server = await _startServer(port);
    _servers.set(bookingId, { port, server });

    console.log(`${C.green}${C.bold}✅ Provider app ready → http://localhost:${port}  (${providerName})${C.reset}\n`);

    const encodedName = encodeURIComponent(providerName);
    exec(`open "http://localhost:${port}?provider=${encodedName}${idParam}"`, err => {
      if (err) console.warn("[ProviderApp] Could not open browser:", err.message);
    });
  } catch (err: any) {
    console.error(`[ProviderApp] Failed to start on port ${port}:`, err.message);
  }
}

export function getProviderAppPort(bookingId: string): number | undefined {
  return _servers.get(bookingId)?.port;
}
