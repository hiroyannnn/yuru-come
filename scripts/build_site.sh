#!/bin/sh
# ブラウザ版（Cloudflare Worker で配信する静的ファイル）を site-dist/ に組み立てる。
# ダッシュボードの HTML・CSS・描画は web/ のものをそのまま使い、データの取り方だけ site/browser.js が差し込む。
set -eu

cd "$(dirname "$0")/.."
OUT="site-dist"

moon build --target js --release

# 念のため、消す対象が期待どおりの名前であることを確かめる
if [ "$OUT" = "site-dist" ] && [ -d "$OUT" ]; then
  rm -rf "./$OUT"
fi
mkdir -p "$OUT"

cp web/style.css web/app.js "$OUT/"
# ローカル版のダッシュボードを、ブラウザ版の入口（browser.js）を読む形にしたもの
sed -e 's|<script src="/app.js"></script>|<script type="module" src="/browser.js"></script>|' \
    -e 's|<h1>yuru-come</h1>|<h1><a href="/" style="color: inherit; text-decoration: none">yuru-come</a></h1>|' \
    web/index.html > "$OUT/app.html"
cp site/index.html site/setup.js site/settings.js site/twitch.js site/browser.js site/overlay.html "$OUT/"
cp _build/js/release/build/jsapi/jsapi.js "$OUT/jsapi.js"
echo "built $OUT/"
