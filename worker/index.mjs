// yuru-come ブラウザ版の Worker。静的ファイル（site-dist/）を配り、/api/judge で Jev への中継だけを行う。
//
// - 中継は {comment, context} だけを受け取り、Jev への質問は jsapi.judge_body が組む（任意の質問を通さない）
// - 通す前に関門（GateDO、1 つだけ）で IP ごとの流量制限と 1 日の予算を確かめる。超えたら 429
// - Jev のキーは Worker の secret（JEV_API_KEY）。ブラウザには出さない
import { DurableObject } from "cloudflare:workers";
// 読み込み順が大事: seed_begin → jsapi → seed_end（理由は seed_begin.mjs）
import "./seed_begin.mjs";
import * as yc from "../_build/js/release/build/jsapi/jsapi.js";
import "./seed_end.mjs";

const MAX_BODY_CHARS = 4000;
const JEV_TIMEOUT_MS = 10_000;

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

export class GateDO extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      const saved = (await ctx.storage.get("budget")) || "";
      yc.gate_new(
        Number(env.DAILY_LIMIT || 30000),
        Number(env.PER_IP_PER_MINUTE || 300),
        60_000,
        saved,
      );
    });
  }

  async fetch(request) {
    const { ip } = await request.json();
    const verdict = yc.gate_check(String(ip || "unknown"), Date.now());
    if (verdict === "ok") await this.ctx.storage.put("budget", yc.gate_dump());
    return json({ verdict });
  }
}

async function judge(request, env) {
  // ほかのサイトのページからは使わせない（同じオリジンのブラウザ版だけ）
  const origin = request.headers.get("Origin");
  if (origin && origin !== new URL(request.url).origin) return json({ error: "origin" }, 403);
  const text = await request.text();
  if (text.length > MAX_BODY_CHARS) return json({ error: "too_large" }, 413);
  const body = yc.judge_body(text, env.JEV_MODEL || "typesafe-ai/jev");
  if (!body) return json({ error: "bad_request" }, 400);

  const ip = request.headers.get("CF-Connecting-IP") || "unknown";
  const gate = env.GATE.get(env.GATE.idFromName("gate"));
  const { verdict } = await (await gate.fetch("https://gate/check", {
    method: "POST",
    body: JSON.stringify({ ip }),
  })).json();
  if (verdict !== "ok") return json({ error: verdict }, 429);

  if (!env.JEV_API_KEY) return json({ error: "not_configured" }, 503);
  try {
    const response = await fetch(`${String(env.JEV_URL).replace(/\/$/, "")}/v1/systemone`, {
      method: "POST",
      headers: { Authorization: `Bearer ${env.JEV_API_KEY}`, "Content-Type": "application/json" },
      body,
      signal: AbortSignal.timeout(JEV_TIMEOUT_MS),
    });
    return new Response(await response.text(), {
      status: response.status,
      headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
    });
  } catch (_) {
    return json({ error: "upstream" }, 502);
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/api/judge") {
      if (request.method !== "POST") return json({ error: "method" }, 405);
      return judge(request, env);
    }
    return env.ASSETS.fetch(request);
  },
};
