// yuru-come ダッシュボード。/api/state を 1 秒ごとに読んで描き直すだけの素の JS。
// コメント本文は信用できない入力なので、必ず textContent で入れる（innerHTML に渡さない）。
"use strict";

const KINDS = {
  question: "質問", request: "リクエスト", feedback: "感想", correction: "指摘",
  greeting: "挨拶", first_time: "初見", trouble: "トラブル", abuse: "荒らし",
  chatter: "雑談", reaction: "反応", unjudged: "未判定",
};
const KIND_ORDER = ["trouble", "question", "correction", "request", "first_time", "feedback", "greeting", "chatter", "abuse", "reaction", "unjudged"];
const STATUS_TAGS = { pending: "判定待ち", dropped: "未判定（間引き）", failed: "未判定（失敗）" };
const POLL_MS = 1000;

const $ = (id) => document.getElementById(id);
const openedAbuse = new Set();
const dismissed = new Set();

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

// ID をキーに DOM を使い回す。毎秒作り直すと、押している最中のボタンが差し替わってクリックが落ちる。
function syncList(container, items, create, update) {
  const existing = new Map();
  for (const node of container.children) existing.set(node.dataset.key, node);
  const nodes = items.map((item) => {
    const key = String(item.id);
    let node = existing.get(key);
    if (!node) {
      node = create(item);
      node.dataset.key = key;
    }
    update(node, item);
    return node;
  });
  nodes.forEach((node, index) => {
    if (container.children[index] !== node) container.insertBefore(node, container.children[index] || null);
  });
  while (container.children.length > nodes.length) container.lastElementChild.remove();
}

function kindColor(node, kind) {
  node.style.setProperty("--kind", `var(--${kind})`);
}

function ageText(now, at) {
  const sec = Math.max(0, Math.round((now - at) / 1000));
  return sec < 60 ? `${sec}秒前` : `${Math.floor(sec / 60)}分前`;
}

function authorText(comment) {
  const platform = comment.participant_id.split(":")[0];
  const name = comment.author || comment.participant_id.split(":").slice(1).join(":");
  return `${platform} / ${name}`;
}

function createPickup(item) {
  const li = el("li");
  const button = el("button", "pickup");
  button.type = "button";
  const head = el("div", "pickup-head");
  head.append(
    el("span", "badge"), el("span", "priority"), el("span", "echo"),
    el("span", "author"), el("span", "age"),
  );
  button.append(head, el("div", "pickup-text"));
  button.addEventListener("click", () => dismiss(item.id));
  li.append(button);
  return li;
}

function updatePickup(state, li, item) {
  const button = li.firstElementChild;
  kindColor(button, item.kind);
  button.classList.toggle("faded", item.faded);
  button.classList.toggle("pinned", item.pinned);
  button.querySelector(".badge").textContent = KINDS[item.kind] || item.kind;
  button.querySelector(".priority").textContent = `拾う度 ${item.priority.toFixed(1)}`;
  const echo = button.querySelector(".echo");
  echo.textContent = item.count > 1 ? `同じコメント ×${item.count}` : "";
  echo.hidden = item.count <= 1;
  button.querySelector(".author").textContent = authorText(item.comment);
  button.querySelector(".age").textContent = ageText(state.now, item.at);
  button.querySelector(".pickup-text").textContent = item.comment.text;
}

function renderPickups(state) {
  const items = state.pickups.filter((item) => !dismissed.has(item.id));
  $("pickup-count").textContent = items.length ? String(items.length) : "";
  $("pickups-empty").hidden = items.length > 0;
  syncList($("pickups"), items, createPickup, (li, item) => updatePickup(state, li, item));
}

async function dismiss(id) {
  dismissed.add(id);
  if (lastState) renderPickups(lastState);
  try {
    await fetch("/api/dismiss", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id }),
    });
  } catch (_) {
    dismissed.delete(id);
  }
  refresh();
}

function renderBundles(state) {
  const bundles = state.bundles;
  $("bundles-empty").hidden = bundles.length > 0;
  const max = bundles.reduce((m, b) => Math.max(m, b.count), 1);
  $("bundles").replaceChildren(...bundles.map((bundle) => {
    const node = el("span", "bundle");
    // 件数が多い束ほど大きく。18px〜44px
    const size = 18 + Math.round(26 * Math.sqrt(bundle.count / max));
    const text = el("span", "bundle-text", bundle.representative);
    text.style.fontSize = `${size}px`;
    const count = el("span", "bundle-count", `×${bundle.count}`);
    count.style.fontSize = `${Math.max(14, Math.round(size * 0.6))}px`;
    node.append(text, count, el("span", "bundle-people", `${bundle.participants}人`));
    return node;
  }));
}

function renderMood(state) {
  $("rate").textContent = state.mood_short.rate_per_sec.toFixed(1);
  $("participants").textContent = String(state.mood_short.participants);
  $("rate-long").textContent = state.mood_long.rate_per_sec.toFixed(1);
  const byKind = state.mood_long.by_kind;
  const total = state.mood_long.total || 1;
  const kinds = KIND_ORDER.filter((kind) => byKind[kind] > 0);
  $("kindbar").replaceChildren(...kinds.map((kind) => {
    const bar = el("span");
    kindColor(bar, kind);
    bar.style.width = `${(100 * byKind[kind]) / total}%`;
    bar.title = `${KINDS[kind]} ${byKind[kind]}`;
    return bar;
  }));
  $("legend").replaceChildren(...kinds.map((kind) => {
    const li = el("li");
    kindColor(li, kind);
    li.append(`${KINDS[kind]} `, el("b", "", String(byKind[kind])));
    return li;
  }));
}

function renderStats(state) {
  const s = state.stats;
  const ratio = s.queue_limit > 0 ? s.queue_length / s.queue_limit : 0;
  const fill = $("queue-fill");
  fill.style.width = `${Math.min(100, Math.round(ratio * 100))}%`;
  fill.classList.toggle("busy", ratio >= 0.5 && ratio < 0.9);
  fill.classList.toggle("full", ratio >= 0.9);
  const delay = (s.judge_delay_ms / 1000).toFixed(1);
  $("queue-text").textContent = `判定待ち ${s.queue_length} / ${s.queue_limit}（判定中 ${s.in_flight}）／ 直近の判定の遅れ ${delay} 秒`;
  const skipped = s.early + s.inherited;
  const percent = s.received ? Math.round((100 * skipped) / s.received) : 0;
  const stats = $("stats");
  stats.replaceChildren(
    "受信 ", el("b", "", String(s.received)),
    " ／ Jev を省いた ", el("b", "", `${skipped}（${percent}%）`),
    " ／ Jev に投げた ", el("b", "", String(s.sent)),
    " ／ 失敗 ", el("b", "", String(s.failed)),
    " ／ 間引き ", el("b", s.dropped > 0 ? "dropped" : "", String(s.dropped)),
  );
}

function createFlowItem() {
  const li = el("li", "flow-item");
  li.append(el("span", "dot"), el("span", "who"), el("span", "body"), el("span", "tag"));
  return li;
}

function updateFlowItem(li, entry) {
  const folded = entry.kind === "abuse" && !openedAbuse.has(entry.id);
  // 変化が無ければ触らない（判定待ち → 判定済み、折りたたみの開閉のときだけ描き直す）
  const signature = `${entry.kind}|${entry.status}|${entry.pickup_id}|${folded}`;
  if (li.dataset.signature === signature) return;
  li.dataset.signature = signature;
  li.className = "flow-item";
  kindColor(li, entry.kind);
  li.classList.toggle("reaction", entry.kind === "reaction");
  li.classList.toggle("pending", entry.status === "pending");
  li.classList.toggle("picked", entry.pickup_id != null);
  li.classList.toggle("abuse", entry.kind === "abuse");
  li.querySelector(".who").textContent = entry.comment.author || entry.comment.participant_id;
  const body = li.querySelector(".body");
  if (folded) {
    const button = el("button", "", "荒らしと判定（クリックで表示）");
    button.type = "button";
    button.addEventListener("click", () => {
      openedAbuse.add(entry.id);
      if (lastState) renderFlow(lastState);
    });
    body.replaceChildren(button);
  } else {
    body.textContent = entry.comment.text;
  }
  li.querySelector(".tag").textContent = STATUS_TAGS[entry.status] ||
    (entry.kind !== "reaction" && entry.kind !== "unjudged" ? KINDS[entry.kind] : "");
}

function renderFlow(state) {
  syncList($("flow"), state.flow, createFlowItem, updateFlowItem);
}

let lastState = null;

// 画面から消えた ID を覚え続けないようにする
function forgetGone(state) {
  const pickupIds = new Set(state.pickups.map((item) => item.id));
  for (const id of dismissed) if (!pickupIds.has(id)) dismissed.delete(id);
  const flowIds = new Set(state.flow.map((entry) => entry.id));
  for (const id of openedAbuse) if (!flowIds.has(id)) openedAbuse.delete(id);
}

function render(state) {
  lastState = state;
  forgetGone(state);
  $("context").textContent = state.context ? `文脈: ${state.context}` : "";
  renderPickups(state);
  renderBundles(state);
  renderMood(state);
  renderStats(state);
  renderFlow(state);
}

let refreshing = false;

async function refresh() {
  // サーバの返事が遅いときに、ポーリングを積み上げない
  if (refreshing) return;
  refreshing = true;
  try {
    const response = await fetch("/api/state", { cache: "no-store" });
    if (!response.ok) throw new Error(String(response.status));
    render(await response.json());
    $("conn").textContent = "接続中";
    $("conn").classList.remove("down");
  } catch (_) {
    $("conn").textContent = "サーバに接続できません";
    $("conn").classList.add("down");
  } finally {
    refreshing = false;
  }
}

refresh();
setInterval(refresh, POLL_MS);
