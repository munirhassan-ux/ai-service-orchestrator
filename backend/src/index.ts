import dotenv from "dotenv";
dotenv.config();

import express from "express";
import cors from "cors";
import * as path from "path";
import * as fs from "fs";
import { fileURLToPath } from "url";
import { spawn } from "child_process";
import apiRoutes from "./routes/routes.js";

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

app.listen(PORT, () => {
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

  // On every restart: clear all active bans and reset strikes so demo testing is never blocked
  try {
    const abuseFile = path.join(__dirname, "../data/customer_abuse.json");
    if (fs.existsSync(abuseFile)) {
      fs.writeFileSync(abuseFile, JSON.stringify({}, null, 2));
      console.log("🔓 Abuse bans cleared on startup (demo mode)\n");
    }
  } catch { /* non-critical */ }
});

export default app;
