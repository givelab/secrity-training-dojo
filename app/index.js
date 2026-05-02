const express = require("express");
const { Pool } = require("pg");
const config = require("./config");

const app = express();
app.use(express.json());

const pool = new Pool({
  host: config.db.host,
  port: config.db.port,
  database: config.db.name,
  user: config.db.user,
  password: config.db.password,
});

app.get("/health", (req, res) => {
  res.json({ status: "ok", env: config.app.env });
});

// ⚠️ 課題1: /debug エンドポイントが設定情報（クレデンシャルを含む）を返している
app.get("/debug/config", (req, res) => {
  res.json({
    db_host: config.db.host,
    db_user: config.db.user,
    db_password: config.db.password,
    aws_access_key: config.aws.accessKeyId,
    aws_secret: config.aws.secretAccessKey,
  });
});

app.get("/users", async (req, res) => {
  try {
    const result = await pool.query("SELECT id, name, email FROM users");
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(config.app.port, () => {
  console.log(`Server running on port ${config.app.port}`);
  console.log(`Environment: ${config.app.env}`);
});
