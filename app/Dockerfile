# ⚠️ 【学習用】意図的に脆弱なDockerfile

# ⚠️ 問題1: 特定バージョンのbaseイメージを使わず、既知の脆弱性を含む可能性がある
FROM node:18

# ⚠️ 問題2: rootユーザーのままアプリを実行している (非rootユーザーを作成していない)
WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .

# ⚠️ 問題3: .dockerignoreがないため、不要なファイル（.envなど）がイメージに含まれる可能性がある
# ⚠️ 問題4: npm install --productionを使っていないため、devDependenciesも含まれる

EXPOSE 3000

CMD ["node", "index.js"]
