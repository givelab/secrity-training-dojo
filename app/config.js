// ⚠️ 【課題1: クレデンシャル漏洩】
// このファイルには致命的な問題があります。何が問題か特定してください。
//
// ヒント: このファイルをGitにコミットするとどうなるでしょう？
// 　　　　攻撃者はGitHubの公開リポジトリやgit logから何を取得できるでしょう？

const config = {
  db: {
    host: process.env.DB_HOST || "localhost",
    port: parseInt(process.env.DB_PORT || "5432"),
    name: process.env.DB_NAME || "appdb",
    user: process.env.DB_USER || "appuser",
    // ⚠️ 問題1: パスワードがデフォルト値としてコードにハードコードされている
    password: process.env.DB_PASSWORD || "super_secret_password_123",
  },

  aws: {
    region: process.env.AWS_DEFAULT_REGION || "ap-northeast-1",
    // ⚠️ 問題2: AWSのアクセスキーがソースコードに直書きされている
    accessKeyId: process.env.AWS_ACCESS_KEY_ID || "AKIAIOSFODNN7EXAMPLE",
    secretAccessKey:
      process.env.AWS_SECRET_ACCESS_KEY ||
      "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
  },

  app: {
    port: parseInt(process.env.PORT || "3000"),
    env: process.env.NODE_ENV || "development",
  },
};

module.exports = config;
