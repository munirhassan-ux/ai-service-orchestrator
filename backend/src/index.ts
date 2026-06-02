import dotenv from "dotenv";
dotenv.config();

import express from "express";
import cors from "cors";
import * as path from "path";
import { fileURLToPath } from "url";
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
});

export default app;
