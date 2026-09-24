"use strict";

import { loadSettings, saveSettings, loadLabels, overlayUrl, DEFAULTS } from "./settings.js";

const $ = (id) => document.getElementById(id);
const form = $("form");

function fill(settings) {
  $("channel").value = settings.channel;
  $("context").value = settings.context;
  $("pickup_floor").value = settings.pickup_floor;
  $("reaction_words").value = settings.reaction_words.join("\n");
  $("promos").value = settings.promos.length ? JSON.stringify(settings.promos, null, 2) : "";
  $("openai_key").value = settings.openai_key;
  showOverlay(settings);
}

function showOverlay(settings) {
  const show = settings.channel && settings.promos.length > 0;
  $("overlay").hidden = !show;
  if (show) $("overlay-url").textContent = overlayUrl(location.origin, settings);
}

// フォームの値を読む。おかしければ例外（文言つき）
function read() {
  const channel = $("channel").value.trim().replace(/^#/, "").replace(/^https?:\/\/(www\.)?twitch\.tv\//, "").toLowerCase();
  if (!/^[a-z0-9_]{3,25}$/.test(channel)) throw new Error("チャンネル名は英数字と _ の 3〜25 文字です");
  let promos = [];
  const promosText = $("promos").value.trim();
  if (promosText) {
    try {
      promos = JSON.parse(promosText);
    } catch (_) {
      throw new Error("商品・URL が JSON として読めません");
    }
    if (!Array.isArray(promos) || promos.some((p) => !p.label || !p.url || !Array.isArray(p.keywords) || p.keywords.length === 0)) {
      throw new Error("商品・URL は [{label, url, keywords: [...]}] の形で書いてください");
    }
  }
  const floor = Number($("pickup_floor").value);
  return {
    ...loadSettings(),
    channel,
    context: $("context").value.trim(),
    pickup_floor: Number.isFinite(floor) ? floor : DEFAULTS.pickup_floor,
    reaction_words: $("reaction_words").value.split("\n").map((w) => w.trim()).filter(Boolean),
    promos,
    openai_key: $("openai_key").value.trim(),
  };
}

function download(name, text, type) {
  const url = URL.createObjectURL(new Blob([text], { type }));
  const a = Object.assign(document.createElement("a"), { href: url, download: name });
  a.click();
  URL.revokeObjectURL(url);
}

form.addEventListener("submit", (event) => {
  event.preventDefault();
  try {
    saveSettings(read());
    location.href = "/app.html";
  } catch (error) {
    $("error").textContent = error.message;
  }
});

form.addEventListener("input", () => {
  $("error").textContent = "";
  try {
    showOverlay(read());
  } catch (_) {}
});

$("export").addEventListener("click", () => {
  try {
    // キーは書き出さない
    const { openai_key, ...rest } = read();
    download("yuru-come-settings.json", JSON.stringify(rest, null, 2), "application/json");
  } catch (error) {
    $("error").textContent = error.message;
  }
});

$("import").addEventListener("click", () => $("import-file").click());
$("import-file").addEventListener("change", async () => {
  const file = $("import-file").files[0];
  if (!file) return;
  try {
    const imported = JSON.parse(await file.text());
    fill({ ...DEFAULTS, ...imported, openai_key: $("openai_key").value });
  } catch (_) {
    $("error").textContent = "設定ファイルが JSON として読めません";
  }
});

$("labels").addEventListener("click", () => {
  const labels = loadLabels();
  if (!labels) {
    $("error").textContent = "正解データはまだありません（ダッシュボードで拾った・スルーすると貯まります）";
    return;
  }
  download("yuru-come-labels.jsonl", labels, "application/jsonl");
});

$("copy-overlay").addEventListener("click", () => navigator.clipboard.writeText($("overlay-url").textContent));

fill(loadSettings());
