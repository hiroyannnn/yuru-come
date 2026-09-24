// 設定はこのブラウザの localStorage にだけ置く。サーバには送らない。
"use strict";

const KEY = "yuru-come.settings";
const LABELS_KEY = "yuru-come.labels";
// 正解データは 2MB を超えたら古い行から捨てる
const LABELS_MAX_CHARS = 2_000_000;

export const DEFAULTS = {
  channel: "",
  context: "",
  pickup_floor: 0.6,
  priority_threshold: 1.5,
  reaction_words: [],
  promos: [],
  openai_key: "",
  openai_model: "gpt-5.6-luna",
};

export function loadSettings() {
  try {
    return { ...DEFAULTS, ...JSON.parse(localStorage.getItem(KEY) || "{}") };
  } catch (_) {
    return { ...DEFAULTS };
  }
}

export function saveSettings(settings) {
  localStorage.setItem(KEY, JSON.stringify(settings));
}

// エンジンに渡す設定（キーは含めない）
export function engineConfig(settings) {
  return {
    context: settings.context,
    pickup_floor: Number(settings.pickup_floor),
    priority_threshold: Number(settings.priority_threshold),
    reaction_words: settings.reaction_words,
    promos: settings.promos,
  };
}

export function appendLabels(jsonl) {
  if (!jsonl) return;
  try {
    let all = (localStorage.getItem(LABELS_KEY) || "") + jsonl;
    if (all.length > LABELS_MAX_CHARS) {
      all = all.slice(all.length - LABELS_MAX_CHARS);
      all = all.slice(all.indexOf("\n") + 1);
    }
    localStorage.setItem(LABELS_KEY, all);
  } catch (_) {}
}

export function loadLabels() {
  try {
    return localStorage.getItem(LABELS_KEY) || "";
  } catch (_) {
    return "";
  }
}

// オーバーレイ（OBS のブラウザソース）は別のブラウザなので、チャンネルと商品を URL の # に入れて渡す
export function overlayUrl(origin, settings) {
  const promos = btoa(unescape(encodeURIComponent(JSON.stringify(settings.promos))))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return `${origin}/overlay.html#c=${encodeURIComponent(settings.channel)}&p=${promos}`;
}

export function decodePromos(encoded) {
  if (!encoded) return [];
  const base64 = encoded.replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(decodeURIComponent(escape(atob(base64))));
}
