#!/bin/bash
# 人生账本一键部署: build → push main → dist 强推 gh-pages → 轮询线上生效
# 前置: git remote origin 已配好且 token 有效
set -euo pipefail
cd "$(dirname "$0")"

echo "== build =="
cd app && npm run build 2>&1 | grep -E "built in|error" && cd ..

echo "== push main(带重试) =="
git add -A && git commit -m "${1:-chore: deploy}" --allow-empty -q || true
for i in 1 2 3 4 5; do git push origin main && break || { echo retry...; sleep 8; }; done

echo "== 推 gh-pages(保留历史chunk,防旧缓存黑屏) =="
REMOTE=$(git remote get-url origin)
TMPOLD=$(mktemp -d)
if git clone -q --depth 1 --branch gh-pages "$REMOTE" "$TMPOLD" 2>/dev/null; then
  rsync -a --ignore-existing "$TMPOLD/assets/" app/dist/assets/ 2>/dev/null || true
fi
rm -rf "$TMPOLD"
cd app/dist
git init -q && git checkout -q -b gh-pages
git add -A && git commit -qm deploy
REMOTE=$(git -C ../.. remote get-url origin)
for i in 1 2 3 4 5; do git push -f "$REMOTE" gh-pages && break || { echo retry...; sleep 8; }; done
cd .. && rm -rf dist/.git

echo "== 轮询线上 chunk =="
LOCAL=$(grep -oE "index-[A-Za-z0-9_-]+\.js" dist/index.html | head -1)
URL=$(git -C .. remote get-url origin | sed -E 's#https://([^@]+@)?github.com/([^/]+)/([^.]+)(\.git)?#https://\2.github.io/\3/#')
echo "线上地址: $URL"
for i in $(seq 1 40); do
  ONLINE=$(curl -sS --max-time 10 "$URL?t=$(date +%s)" 2>/dev/null | grep -oE "index-[A-Za-z0-9_-]+\.js" | head -1 || true)
  [ "$ONLINE" = "$LOCAL" ] && { echo "✅ 线上已生效: $ONLINE"; exit 0; }
  sleep 10
done
echo "⚠️ 轮询超时,手动确认: $URL"
