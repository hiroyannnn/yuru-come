///|
/// ブラウザ版（web/browser.js）と Jev の中継（worker/index.mjs）から呼ぶ入口。
/// JS との受け渡しは文字列（JSON）と数値だけにする。時刻は Date.now() の値（ミリ秒）を Double で受け取る。
/// エンジンはページに 1 つなので、パッケージ内に 1 つだけ持つ。

///|
/// 判定待ちを JS に渡している間、ID で引けるように持っておく。
priv struct App {
  engine : @lib.Engine
  pending : Map[Int, @lib.Pending]
  mut next_pending_id : Int
  /// 要約を最後に頼んだときのいちばん新しい流れの項目 ID
  mut last_summary_entry : Int
}

///|
let app : Ref[App?] = Ref(None)

///|
fn current() -> App {
  match app.val {
    Some(a) => a
    None => {
      let a : App = {
        engine: @lib.Engine::new(),
        pending: Map([]),
        next_pending_id: 1,
        last_summary_entry: 0,
      }
      app.val = Some(a)
      a
    }
  }
}

///|
fn ms(now : Double) -> Int64 {
  now.to_int64()
}

///|
/// 設定（JSON）からアプリを作り直す。成功なら空文字、失敗ならエラーの文言。
///
/// キー: context, queue_limit, reaction_words, window, threshold, metric,
/// priority_threshold, pickup_floor, promos（`[{label, url, keywords}]`）
pub fn app_new(config : String) -> String {
  let json = @json.parse(config) catch {
    err => return "設定が JSON ではありません: \{err}"
  }
  let engine_config = engine_config_of(json) catch {
    ConfigInvalid(field) =>
      return "設定の \{field} が正しくありません"
  }
  app.val = Some({
    engine: @lib.Engine::new(config=engine_config),
    pending: Map([]),
    next_pending_id: 1,
    last_summary_entry: 0,
  })
  ""
}

///|
priv suberror ConfigInvalid {
  ConfigInvalid(String)
}

///|
fn engine_config_of(json : Json) -> @lib.EngineConfig raise ConfigInvalid {
  guard json is Object(fields) else { raise ConfigInvalid("config") }
  let number = (key : String, default : Double) => {
    match fields.get(key) {
      None | Some(Null) => default
      Some(Number(n, ..)) => n
      Some(_) => raise ConfigInvalid(key)
    }
  }
  let context = match fields.get("context") {
    None | Some(Null) => ""
    Some(String(s)) => s
    Some(_) => raise ConfigInvalid("context")
  }
  let reaction_words : Array[String] = []
  match fields.get("reaction_words") {
    None | Some(Null) => ()
    Some(Array(words)) =>
      for word in words {
        guard word is String(w) else { raise ConfigInvalid("reaction_words") }
        reaction_words.push(w)
      }
    Some(_) => raise ConfigInvalid("reaction_words")
  }
  let metric : @lib.BundleMetric = match fields.get("metric") {
    None | Some(Null) | Some(String("levenshtein")) => NormalizedLevenshtein
    Some(String("jaro-winkler")) => JaroWinkler
    Some(_) => raise ConfigInvalid("metric")
  }
  let promos = match fields.get("promos") {
    None | Some(Null) => []
    Some(list) =>
      @lib.parse_promos(list) catch {
        _ => raise ConfigInvalid("promos")
      }
  }
  @lib.EngineConfig::new(
    context~,
    queue_limit=number("queue_limit", 50.0).to_int(),
    reaction_words~,
    bundle=@lib.BundleConfig::new(
      window_ms=(number("window", 30.0) * 1000.0).to_int64(),
      threshold=number("threshold", 0.85),
      metric~,
    ),
    pickup=@lib.PickupConfig::new(
      priority_threshold=number("priority_threshold", 1.5),
      kind_floor=number("pickup_floor", 0.6),
    ),
    promos~,
  )
}

///|
/// Twitch に匿名でつなぐときに送る行（CRLF 区切り）。
pub fn app_login_lines(nick : String, channel : String) -> String {
  @lib.twitch_login_lines(nick, channel).map(line => "\{line}\r\n").join("")
}

///|
/// WebSocket で受け取ったデータ（複数行のこともある）を処理する。
/// 発言は取り込み、PING には返答行を返す。返す行が無ければ空文字。
pub fn app_irc_line(data : String, now : Double) -> String {
  let app = current()
  let replies = StringBuilder()
  for raw in data.split("\n") {
    let line = raw.trim_end(chars="\r").to_owned()
    if line.is_empty() {
      continue
    }
    match @lib.parse_irc_line(line) {
      Ping(payload) => replies.write_string("\{@lib.pong_line(payload)}\r\n")
      Chat(comment) => app.engine.ingest({ ..comment, at: ms(now), }, ms(now))
      Other(_) => ()
    }
  }
  replies.to_string()
}

///|
/// 次の判定待ちを `{id, comment, context}` で返す。無ければ空文字。
pub fn app_take_next() -> String {
  let app = current()
  guard app.engine.take_next() is Some(pending) else { return "" }
  let id = app.next_pending_id
  app.next_pending_id += 1
  app.pending[id] = pending
  (
    {
      "id": id,
      "comment": pending.comment.text,
      "context": app.engine.context(),
    } : Json).stringify()
}

///|
/// 判定結果（Jev のレスポンス本文）を返す。空文字や解釈できない本文は判定失敗として扱う。
pub fn app_complete(id : Int, response : String, now : Double) -> Unit {
  let app = current()
  guard app.pending.get(id) is Some(pending) else { return }
  app.pending.remove(id)
  let triage = if response.is_empty() {
    None
  } else {
    Some(@lib.parse_response_text(response)) catch {
      _ => None
    }
  }
  app.engine.complete(pending, triage, ms(now))
}

///|
/// ダッシュボードに渡す全状態（ローカル版の `/api/state` と同じ形）。
pub fn app_state(now : Double) -> String {
  current().engine.state(ms(now)).to_json().stringify()
}

///|
/// 気になるコメントを消す。`action` は "picked"（拾った）か "skipped"（スルー）。
pub fn app_dismiss(id : Int, action : String, now : Double) -> Bool {
  let outcome : @lib.PickupOutcome = if action == "skipped" {
    Skipped
  } else {
    Picked
  }
  current().engine.resolve_pickup(id, outcome, ms(now))
}

///|
/// 溜まった正解データを JSONL で取り出す。無ければ空文字。
pub fn app_take_labels() -> String {
  current().engine
  .take_labels()
  .map(label => label.to_json().stringify() + "\n")
  .join("")
}

///|
/// 要約を頼む価値があれば、LLM への入力 `{system, user}` を返す。無ければ空文字。
pub fn app_summary_prompt(now : Double) -> String {
  let app = current()
  let state = app.engine.state(ms(now))
  guard @lib.summary_needed(state, last_entry_id=app.last_summary_entry) else {
    return ""
  }
  app.last_summary_entry = state.flow[0].id
  let prompt = @lib.summary_prompt(state)
  ({ "system": prompt.system, "user": prompt.user } : Json).stringify()
}

///|
/// LLM が書いた一文を整えて覚える。
pub fn app_set_summary(text : String, now : Double) -> Unit {
  let cleaned = @lib.clean_summary(text)
  if !cleaned.is_empty() {
    current().engine.set_summary(cleaned, ms(now))
  }
}

///|
/// 中継: `{comment, context}` から Jev のリクエスト本文を組む。不正な入力は空文字。
pub fn judge_body(request : String, model : String) -> String {
  let json = @json.parse(request) catch { _ => return "" }
  let parsed = @lib.parse_judge_request(json) catch { _ => return "" }
  @lib.build_request(parsed.comment, context=parsed.context, model~).stringify()
}

///|
/// 中継の関門（Durable Object に 1 つ）。
priv struct Gate {
  budget : @lib.DailyBudget
  limiter : @lib.RateLimiter
}

///|
let gate : Ref[Gate?] = Ref(None)

///|
/// 関門を作る。`saved` は `gate_dump` の結果（空なら新規）。
pub fn gate_new(
  daily_limit : Int,
  per_ip : Int,
  window_ms : Double,
  saved : String,
) -> Unit {
  let saved_json = if saved.is_empty() {
    Json::null()
  } else {
    @json.parse(saved) catch {
      _ => Json::null()
    }
  }
  gate.val = Some({
    budget: @lib.DailyBudget::restore(saved_json, limit=daily_limit),
    limiter: @lib.RateLimiter::new(limit=per_ip, window_ms=window_ms.to_int64()),
  })
}

///|
/// 1 回の判定を通してよいか。"ok" / "rate"（その IP が多すぎる）/ "budget"（今日の予算切れ）。
/// 流量制限を先に見るので、弾かれた試行は予算を減らさない。
pub fn gate_check(ip : String, now : Double) -> String {
  guard gate.val is Some(g) else { return "budget" }
  if !g.limiter.allow(ip, ms(now)) {
    return "rate"
  }
  if !g.budget.spend(ms(now)) {
    return "budget"
  }
  "ok"
}

///|
/// 予算の状態を保存用に返す。
pub fn gate_dump() -> String {
  match gate.val {
    Some(g) => g.budget.dump().stringify()
    None => ""
  }
}

///|
/// オーバーレイ用。URL の QR コードを SVG で返す。作れなければ空文字。
pub fn qr(text : String) -> String {
  @lib.qr_svg(text).unwrap_or("")
}
