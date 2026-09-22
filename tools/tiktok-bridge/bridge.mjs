#!/usr/bin/env node
// TikTok LIVE のコメントを `参加者ID<TAB>発言` で標準出力に流す小さなブリッジ。
//
//   node tools/tiktok-bridge/bridge.mjs <TikTok のユーザー名> \
//     | moon run --target native cmd/yuru-come -- --source stdin --stdin-source tiktok
//
// TikTok には公式のコメント取得 API が無いので、非公式ライブラリ tiktok-live-connector を使う。
// package.json では MIT で配布された最後の版 2.4.0 に固定している（2.4.1 以降は AGPL-3.0-only）。
// TikTok 側の仕様変更で予告なく動かなくなることがある。ログは標準エラー出力に出す。
import { TikTokLiveConnection, WebcastEvent } from "tiktok-live-connector";

const uniqueId = process.argv[2];
if (!uniqueId) {
  console.error("使い方: node bridge.mjs <TikTok のユーザー名（@ なし）>");
  process.exit(1);
}

const connection = new TikTokLiveConnection(uniqueId, {});

// TAB と改行は区切りに使うので、空白に置き換える
const clean = (text) => String(text ?? "").replace(/[\t\r\n]+/g, " ").trim();

connection.on(WebcastEvent.CHAT, (data) => {
  const id = clean(data.user?.uniqueId || data.uniqueId || "anon");
  const comment = clean(data.comment);
  if (comment) process.stdout.write(`${id}\t${comment}\n`);
});

connection.on(WebcastEvent.STREAM_END, () => {
  console.error("[tiktok-bridge] 配信が終了しました");
  process.exit(0);
});

connection.on(WebcastEvent.DISCONNECTED, () => {
  console.error("[tiktok-bridge] 切断されました");
  process.exit(1);
});

try {
  const state = await connection.connect();
  console.error(`[tiktok-bridge] @${uniqueId} のルーム ${state.roomId} に接続しました`);
} catch (err) {
  console.error(`[tiktok-bridge] 接続できません（配信していない、または TikTok 側の仕様変更）: ${err}`);
  process.exit(1);
}
