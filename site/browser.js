// ブラウザ版のダッシュボード。エンジン（MoonBit を JS にビルドした jsapi.js）をこのタブの中で動かす。
// コメントは Twitch から直接受け取り、判定だけを運営者の中継（/api/judge）経由で Jev に頼む。
// 要約は、利用者が自分の OpenAI キーを入れたときだけ、このブラウザから直接 OpenAI を呼ぶ。
"use strict";

import * as yc from "./jsapi.js";
import { connectTwitch } from "./twitch.js";
import { loadSettings, engineConfig, appendLabels } from "./settings.js";

const JUDGE_WORKERS = 3;
const JUDGE_TIMEOUT_MS = 10_000;
const SUMMARY_INTERVAL_MS = 30_000;

const settings = loadSettings();
if (!settings.channel) {
  location.replace("/");
  throw new Error("channel is not set");
}

const configError = yc.app_new(JSON.stringify(engineConfig(settings)));
if (configError) alert(`設定を読めませんでした: ${configError}`);

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// --- Twitch ---
let twitch = { ok: false, text: "接続を準備しています…" };
connectTwitch(settings.channel, {
  loginLines: yc.app_login_lines,
  onData: (text) => yc.app_irc_line(text, Date.now()),
  onStatus: (status) => { twitch = status; },
});

// --- 判定 ---
// 中継が 429 を返したら、しばらく判定をやめて束ねと早期判定だけで動く（縮退モード）
let degraded = null;

async function judgeOnce(pending) {
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      const response = await fetch("/api/judge", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ comment: pending.comment, context: pending.context }),
        signal: AbortSignal.timeout(JUDGE_TIMEOUT_MS),
      });
      if (response.ok) {
        degraded = null;
        return await response.text();
      }
      if (response.status === 429) {
        const { error } = await response.json().catch(() => ({}));
        const budget = error === "budget";
        degraded = {
          text: budget
            ? "今日の判定枠を使い切りました。束ねと早期判定だけで動いています"
            : "判定が混み合っています。少し待ってから再開します",
          until: Date.now() + (budget ? 10 * 60_000 : 30_000),
        };
        return "";
      }
      if (response.status < 500) return "";
    } catch (_) {
      // タイムアウトや通信エラーは 1 回だけやり直す
    }
    await sleep(300);
  }
  return "";
}

async function judgeWorker() {
  for (;;) {
    const next = yc.app_take_next();
    if (!next) {
      await sleep(150);
      continue;
    }
    const pending = JSON.parse(next);
    const text = degraded && Date.now() < degraded.until ? "" : await judgeOnce(pending);
    yc.app_complete(pending.id, text, Date.now());
  }
}
for (let i = 0; i < JUDGE_WORKERS; i += 1) judgeWorker();

// --- 要約（自分の OpenAI キーがあるときだけ） ---
async function chat(prompt, reasoning) {
  const body = {
    model: settings.openai_model || "gpt-5.6-luna",
    messages: [
      { role: "system", content: prompt.system },
      { role: "user", content: prompt.user },
    ],
    max_completion_tokens: 200,
  };
  if (reasoning) body.reasoning_effort = reasoning;
  return fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${settings.openai_key}` },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(20_000),
  });
}

async function summarize() {
  const raw = yc.app_summary_prompt(Date.now());
  if (!raw) return;
  const prompt = JSON.parse(raw);
  try {
    // gpt-5.6 系は reasoning_effort=none が最速。受け付けないモデルなら外して送り直す
    let response = await chat(prompt, "none");
    if (response.status === 400) response = await chat(prompt, null);
    if (!response.ok) return;
    const data = await response.json();
    const text = data?.choices?.[0]?.message?.content;
    if (typeof text === "string") yc.app_set_summary(text, Date.now());
  } catch (_) {}
}
if (settings.openai_key) setInterval(summarize, SUMMARY_INTERVAL_MS);

// --- 正解データ（拾った・スルー・期限切れ）をこのブラウザに貯める ---
setInterval(() => appendLabels(yc.app_take_labels()), 5_000);
addEventListener("pagehide", () => appendLabels(yc.app_take_labels()));

// --- 画面（web/app.js）にデータの取り方を渡してから読み込む ---
window.YURU_SOURCE = {
  getState: () => JSON.parse(yc.app_state(Date.now())),
  dismiss: (id, action) => yc.app_dismiss(id, action, Date.now()),
  connection: () => {
    if (degraded && Date.now() < degraded.until) return { ok: false, text: degraded.text };
    return twitch;
  },
};
const script = document.createElement("script");
script.src = "/app.js";
document.body.append(script);
