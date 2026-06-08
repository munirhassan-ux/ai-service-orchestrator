import dotenv from "dotenv";
dotenv.config();

import express from "express";
import cors from "cors";
import * as path from "path";
import * as fs from "fs";
import { fileURLToPath } from "url";
import { spawn, execSync } from "child_process";
import apiRoutes from "./routes/routes.js";
import { startSlaMonitor } from "./agents/slaMonitor.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// Serve static files (trace viewer)
app.use(express.static(path.join(__dirname, "../public")));

// All API routes under /api
app.use("/api", apiRoutes);

// Health check
app.get("/health", (req, res) => {
  res.json({
    status: "ok",
    service: "Haazir AI Orchestrator",
    version: "1.0.0",
    timestamp: new Date().toISOString(),
  });
});

const server = app.listen(PORT, () => {
  console.log(`\n🚀 Haazir backend running on http://localhost:${PORT}`);
  console.log(`📋 Health check: http://localhost:${PORT}/health`);
  console.log(`🤖 Orchestrate: POST http://localhost:${PORT}/api/orchestrate\n`);

  // Auto-build provider Flutter web app in background if not already built
  const providerBuildDir = path.join(__dirname, "../../frontend/build/web_provider");
  if (!fs.existsSync(path.join(providerBuildDir, "index.html"))) {
    const frontendDir = path.join(__dirname, "../../frontend");
    console.log("⚙️  Provider app not built — building in background (ready before first booking)...");
    const build = spawn("flutter", [
      "build", "web",
      "-t", "lib/main_provider.dart",
      "-o", "build/web_provider",
      "--no-tree-shake-icons",
    ], { cwd: frontendDir, stdio: "pipe" });
    build.on("close", code => {
      if (code === 0) console.log("✅ Provider app build complete — auto-launch ready.");
      else console.warn(`⚠️  Provider app build exited with code ${code}`);
    });
  } else {
    console.log("✅ Provider app build found — auto-launch ready.\n");
  }

  // On every restart: wipe all job listings for a clean demo slate
  try {
    const dataDir = path.join(__dirname, "../data");

    fs.writeFileSync(path.join(dataDir, "mock_bookings.json"),    JSON.stringify({ bookings: [] }, null, 2));
    fs.writeFileSync(path.join(dataDir, "sessions.json"),         JSON.stringify({ sessions: [] }, null, 2));
    fs.writeFileSync(path.join(dataDir, "mock_schedule.json"),    JSON.stringify({}, null, 2));
    fs.writeFileSync(path.join(dataDir, "mock_contracts.json"),   JSON.stringify([], null, 2));
    fs.writeFileSync(path.join(dataDir, "mock_negotiations.json"),JSON.stringify([], null, 2));
    fs.writeFileSync(path.join(dataDir, "mock_disputes.json"),    JSON.stringify([], null, 2));

    // Clear per-booking invoice files
    const invoicesDir = path.join(dataDir, "invoices");
    if (fs.existsSync(invoicesDir)) {
      for (const f of fs.readdirSync(invoicesDir)) {
        if (f.endsWith(".json")) fs.unlinkSync(path.join(invoicesDir, f));
      }
    }

    // Clear agent trace files
    const tracesDir = path.join(dataDir, "agent_traces");
    if (fs.existsSync(tracesDir)) {
      for (const f of fs.readdirSync(tracesDir)) {
        if (f.endsWith(".json")) fs.unlinkSync(path.join(tracesDir, f));
      }
    }

    // Clear abuse bans
    fs.writeFileSync(path.join(dataDir, "customer_abuse.json"), JSON.stringify({}, null, 2));

    console.log("🧹 Job listings cleared on startup (clean demo slate)\n");
  } catch (e) { console.warn("⚠️  Startup reset partial:", (e as Error).message); }

  startSlaMonitor();
});

server.on("error", (err: NodeJS.ErrnoException) => {
  if (err.code === "EADDRINUSE") {
    console.warn(`\n⚠️  Port ${PORT} already in use — killing stale process and retrying...\n`);
    try {
      execSync(`lsof -ti :${PORT} | xargs kill -9`, { stdio: "ignore" });
    } catch { /* nothing was there */ }
    setTimeout(() => server.listen(PORT), 800);
  } else {
    throw err;
  }
});

export default app;
