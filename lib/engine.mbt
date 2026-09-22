///|
pub(all) struct EngineConfig {
  /// Jev に渡す配信の文脈（配信タイトルや話題）。空なら渡さない
  context : String
  /// Jev 待ちキューの上限
  queue_limit : Int
  /// 「全部の流れ」に保持する件数
  flow_limit : Int
  /// 早期判定の辞書に足す語
  reaction_words : Array[String]
  bundle : BundleConfig
  pickup : PickupConfig
} derive(Debug)

///|
pub fn EngineConfig::new(
  context? : String = "",
  queue_limit? : Int = 50,
  flow_limit? : Int = 200,
  reaction_words? : Array[String] = [],
  bundle? : BundleConfig = BundleConfig::new(),
  pickup? : PickupConfig = PickupConfig::new(),
) -> EngineConfig {
  { context, queue_limit, flow_limit, reaction_words, bundle, pickup, }
}

///|
/// 「全部の流れ」の 1 件が、どうやって種類を決められたか。
pub(all) enum JudgeStatus {
  /// 早期判定で reaction に決まった（Jev を呼んでいない）
  Early
  /// Jev の判定待ち
  Pending
  /// Jev が判定した
  Judged
  /// 同じ束の先頭の判定に相乗りした（Jev を呼んでいない）
  Inherited
  /// 流量制御で落とした（未判定）
  Dropped
  /// 判定に失敗した（未判定）
  Failed
} derive(Debug, Eq)

///|
pub impl ToJson for JudgeStatus with fn to_json(self) {
  Json::string(
    match self {
      Early => "early"
      Pending => "pending"
      Judged => "judged"
      Inherited => "inherited"
      Dropped => "dropped"
      Failed => "failed"
    },
  )
}

///|
/// 「全部の流れ」の 1 件。
pub(all) struct FlowEntry {
  id : Int
  comment : Comment
  mut kind : Kind
  mut priority : Double?
  mut status : JudgeStatus
  /// 拾い上げに入った（または相乗りした）項目の ID
  mut pickup_id : Int?
} derive(Debug, ToJson)

///|
/// Jev の判定を待っているコメント。`take_next` で受け取り、`complete` で結果を返す。
pub struct Pending {
  comment : Comment
  /// 流れの項目そのもの。流れの上限で押し出されたあとでも、判定結果の反映と Sink への通知ができる
  entry : FlowEntry
  /// 空気の記録 ID（判定後に種類を付け替える）
  mood_id : Int
  /// この束の先頭として判定結果を残す先。類似度だけで束に入って個別に判定するコメントは None
  verdict : BundleVerdict?
  /// 正規化後の文字数（落とす候補を選ぶのに使う）
  length : Int
  /// エンジンに届いた時刻
  at : Int64
}

///|
/// 処理の内訳。
pub(all) struct EngineStats {
  received : Int
  /// 早期判定で reaction に決めた件数
  early : Int
  /// 同じ束の判定に相乗りした件数
  inherited : Int
  /// Jev に投げた件数
  sent : Int
  judged : Int
  failed : Int
  /// 流量制御で落とした件数
  dropped : Int
  queue_length : Int
  queue_limit : Int
  in_flight : Int
  /// 直近の判定が、コメントの到着から何ミリ秒遅れて返ったか
  judge_delay_ms : Int64
} derive(Debug, Eq, ToJson)

///|
/// ダッシュボードに渡す全状態。
pub(all) struct EngineState {
  now : Int64
  context : String
  pickups : Array[PickupView]
  /// 時間窓の中の束（2 件以上、件数の多い順）
  bundles : Array[BundleSummary]
  /// 30 秒窓の空気
  mood_short : MoodSnapshot
  /// 5 分窓の空気
  mood_long : MoodSnapshot
  /// 新しい順
  flow : Array[FlowEntry]
  stats : EngineStats
  /// いまの空気の一文
  summary : Summary
} derive(Debug, ToJson)

///|
/// 種類が決まったコメントの通知先。
pub(open) trait Sink {
  fn on_entry(Self, FlowEntry) -> Unit
}

///|
/// コメントの入口。`submit` にコメントを渡すとエンジンに取り込まれる。
/// `submit` は判定を待たずにすぐ戻る。`run` は Source が尽きるまで（チャットなら接続が切れるまで）戻らない。
pub(open) trait Source {
  async fn run(Self, submit : async (Comment) -> Unit) -> Unit
}

///|
pub const MOOD_SHORT_WINDOW_MS : Int64 = 30_000

///|
pub const MOOD_LONG_WINDOW_MS : Int64 = 300_000

///|
/// 束ごとの判定結果。同じ束に入った後続のコメントは、これに相乗りして Jev を呼ばない。
pub struct BundleVerdict {
  /// 先頭のコメントの判定結果。None は判定待ち
  mut decided : (Kind, Double?)?
  mut pickup_id : Int?
  /// 先頭の判定を待っている後続（流れの項目と、空気の記録 ID）
  followers : Array[(FlowEntry, Int)]
  created_at : Int64
  /// 最後に触った時刻
  mut touched_at : Int64
}

///|
fn BundleVerdict::new(decided : (Kind, Double?)?, now : Int64) -> BundleVerdict {
  { decided, pickup_id: None, followers: [], created_at: now, touched_at: now, }
}

///|
/// 正規化 → 束ね → 早期判定 → （必要なら）Jev 仕分け → 各集計へ反映 → Sink へ通知、を行うエンジン。
///
/// 判定そのもの（Jev への問い合わせ）は行わない同期の状態機械。
/// 呼び出し側が `take_next` で判定待ちを受け取り、結果を `complete` で返す。
/// `ingest` は判定を待たないので、Jev が遅くても取り込みは止まらない。
pub struct Engine {
  config : EngineConfig
  rules : ReactionRules
  bundler : Bundler
  pickup : PickupList
  mood : Mood
  sinks : Array[&Sink]
  /// 古い順
  flow : Array[FlowEntry]
  /// 古い順
  queue : Array[Pending]
  verdicts : Map[String, BundleVerdict]
  mut next_entry_id : Int
  mut received : Int
  mut early : Int
  mut inherited : Int
  mut sent : Int
  mut judged : Int
  mut failed : Int
  mut dropped : Int
  mut in_flight : Int
  mut judge_delay_ms : Int64
  /// LLM が書いた最新の一文と、その時刻
  mut llm_summary : (String, Int64)?
}

///|
pub fn Engine::new(config? : EngineConfig = EngineConfig::new()) -> Engine {
  {
    config,
    rules: ReactionRules::new(extra_words=config.reaction_words),
    bundler: Bundler::new(config=config.bundle),
    pickup: PickupList::new(config=config.pickup),
    mood: Mood::new(retention_ms=MOOD_LONG_WINDOW_MS),
    sinks: [],
    flow: [],
    queue: [],
    verdicts: Map([]),
    next_entry_id: 1,
    received: 0,
    early: 0,
    inherited: 0,
    sent: 0,
    judged: 0,
    failed: 0,
    dropped: 0,
    in_flight: 0,
    judge_delay_ms: 0,
    llm_summary: None,
  }
}

///|
/// Sink を接続する。複数接続できる。
pub fn Engine::add_sink(self : Engine, sink : &Sink) -> Unit {
  self.sinks.push(sink)
}

///|
/// Jev に渡す配信の文脈。
pub fn Engine::context(self : Engine) -> String {
  self.config.context
}

///|
/// コメントを 1 件取り込む。判定は待たない。
pub fn Engine::ingest(self : Engine, comment : Comment, now : Int64) -> Unit {
  self.received += 1
  self.forget_stale_verdicts(now)
  let key = normalize(comment.text, emotes=comment.emotes)
  let hit = self.bundler.add(key, comment, now)
  let entry : FlowEntry = {
    id: self.next_entry_id,
    comment,
    kind: Unjudged,
    priority: None,
    status: Pending,
    pickup_id: None,
  }
  self.next_entry_id += 1
  self.flow.push(entry)
  if self.flow.length() > self.config.flow_limit {
    self.flow.remove(0) |> ignore
  }
  let label = comment.text.trim(chars=" \t\r\n\u3000").to_owned()
  let mood_id = self.mood.record(
    now,
    comment.participant_id,
    Unjudged,
    reaction=hit.key,
    label~,
  )
  if self.rules.is_reaction(comment.text, emotes=comment.emotes) {
    self.early += 1
    if !self.verdicts.contains(hit.key) {
      self.verdicts[hit.key] = BundleVerdict::new(Some((Reaction, None)), now)
    }
    return self.settle(entry, mood_id, Reaction, None, Early)
  }
  match self.verdicts.get(hit.key) {
    // 反応の束（早期判定で決まったもの）には、疑問符つきのコメントを相乗りさせない
    Some({ decided: Some((kind, priority)), .. } as verdict) if !(kind
      is Unjudged) &&
      (hit.exact || !is_pickup_kind(kind)) &&
      !(kind is Reaction && asks_question(comment.text)) => {
      verdict.touched_at = now
      self.inherited += 1
      self.follow(entry, mood_id, verdict, kind, priority)
    }
    Some({ decided: None, .. } as verdict) if hit.exact => {
      verdict.touched_at = now
      verdict.followers.push((entry, mood_id))
    }
    existing => {
      // 束の先頭（または先頭が未判定に終わった束の仕切り直し）なら、判定結果を束に残す。
      // 拾うべき種類の束や判定待ちの束に類似度だけで入ったコメントは、束に触らず個別に判定する
      let verdict = if existing
        is (None | Some({ decided: Some((Unjudged, _)), .. })) {
        let verdict = BundleVerdict::new(None, now)
        self.verdicts[hit.key] = verdict
        Some(verdict)
      } else {
        None
      }
      self.queue.push({
        comment,
        entry,
        mood_id,
        verdict,
        length: key.char_length(),
        at: now,
      })
      self.shed_overflow()
    }
  }
}

///|
fn asks_question(text : String) -> Bool {
  text.contains("?") || text.contains("？")
}

///|
/// 間引くときに後回しにするコメントか。疑問符つきと、配信トラブルの報告らしいもの。
fn worth_keeping(comment : Comment) -> Bool {
  asks_question(comment.text) ||
  trouble_hints.iter().any(hint => comment.text.contains(hint))
}

///|
/// 配信トラブルの報告によく出る語。間引きの優先順位にだけ使う（判定は Jev がする）。
let trouble_hints : Array[String] = [
  "音", "声", "マイク", "画面", "映像", "配信", "止ま", "固ま", "落ち", "聞こえ", "見えな", "カク",
  "ラグ", "遅延", "ノイズ",
]

///|
/// 候補の中から落とすものを選ぶ。後回しにしないものを優先し、同じなら短いもの。
fn pick_victim(candidates : ArrayView[Pending]) -> Int {
  let mut victim = 0
  for i in 1..<candidates.length() {
    let keep_current = worth_keeping(candidates[victim].comment)
    let keep_candidate = worth_keeping(candidates[i].comment)
    if (keep_current && !keep_candidate) ||
      (keep_current == keep_candidate &&
      candidates[i].length < candidates[victim].length) {
      victim = i
    }
  }
  victim
}

///|
/// 配信者が拾うべき種類か（類似度だけで束に入ったコメントを相乗りさせない種類）。
fn is_pickup_kind(kind : Kind) -> Bool {
  kind is (Question | Request | Correction | FirstTime | Trouble)
}

///|
/// キューが上限を超えていたら、古い半分のうちいちばん短いコメントを未判定のまま流す。
fn Engine::shed_overflow(self : Engine) -> Unit {
  let limit = if self.config.queue_limit > 0 {
    self.config.queue_limit
  } else {
    0
  }
  while self.queue.length() > limit {
    // 古い半分のうちいちばん短いものを落とす。疑問符つきとトラブルらしいものは後回しにし、
    // 古い半分が全部そうなら、新しいものを除いた全体から探す
    let older_half = (self.queue.length() + 1) / 2
    let mut victim = pick_victim(self.queue[:older_half])
    if worth_keeping(self.queue[victim].comment) && self.queue.length() > 1 {
      victim = pick_victim(self.queue[:self.queue.length() - 1])
    }
    let pending = self.queue.remove(victim)
    self.resolve(pending, Unjudged, None, Dropped)
  }
}

///|
/// 次に判定するコメントを取り出す。無ければ None。
/// 新しいものから判定する。滞留したときに、拾い上げが何十秒も前のコメントばかりになるのを避けるため。
/// 古いものは後回しになり、あふれたら `shed_overflow` が未判定のまま流す。
pub fn Engine::take_next(self : Engine) -> Pending? {
  guard self.queue.pop() is Some(pending) else { return None }
  self.sent += 1
  self.in_flight += 1
  Some(pending)
}

///|
/// `take_next` で受け取ったコメントの判定結果を返す。`triage` が None なら判定失敗。
pub fn Engine::complete(
  self : Engine,
  pending : Pending,
  triage : Triage?,
  now : Int64,
) -> Unit {
  self.in_flight -= 1
  self.judge_delay_ms = now - pending.at
  match triage {
    Some(triage) => {
      self.judged += 1
      self.resolve(pending, triage.kind, Some(triage.priority), Judged, now~)
    }
    None => {
      self.failed += 1
      self.resolve(pending, Unjudged, None, Failed, now~)
    }
  }
}

///|
/// 判定待ちだったコメントの種類を確定し、束の先頭なら結果を束に残して後続にも配る。
fn Engine::resolve(
  self : Engine,
  pending : Pending,
  kind : Kind,
  priority : Double?,
  status : JudgeStatus,
  now? : Int64,
) -> Unit {
  let pickup_id = match (now, priority) {
    (Some(now), Some(priority)) =>
      self.pickup.offer(pending.comment, kind, priority, now)
    _ => None
  }
  pending.entry.pickup_id = pickup_id
  self.settle(pending.entry, pending.mood_id, kind, priority, status)
  guard pending.verdict is Some(verdict) else { return }
  verdict.decided = Some((kind, priority))
  verdict.pickup_id = pickup_id
  if now is Some(now) {
    verdict.touched_at = now
  }
  for follower in verdict.followers {
    let (entry, mood_id) = follower
    if kind is Unjudged {
      // 先頭が未判定に終わったら、相乗り待ちも同じ扱いで流れにだけ出す
      self.settle(entry, mood_id, Unjudged, None, status)
    } else {
      self.inherited += 1
      self.follow(entry, mood_id, verdict, kind, priority)
    }
  }
  verdict.followers.clear()
}

///|
/// 束の先頭の判定に相乗りさせる。先頭が拾い上げに残っていれば、その件数を増やす。
fn Engine::follow(
  self : Engine,
  entry : FlowEntry,
  mood_id : Int,
  verdict : BundleVerdict,
  kind : Kind,
  priority : Double?,
) -> Unit {
  if verdict.pickup_id is Some(id) && self.pickup.bump(id) {
    entry.pickup_id = Some(id)
  }
  self.settle(entry, mood_id, kind, priority, Inherited)
}

///|
/// 流れの項目の種類を確定し、空気に反映して Sink に通知する。
fn Engine::settle(
  self : Engine,
  entry : FlowEntry,
  mood_id : Int,
  kind : Kind,
  priority : Double?,
  status : JudgeStatus,
) -> Unit {
  entry.kind = kind
  entry.priority = priority
  entry.status = status
  if status is Dropped {
    self.dropped += 1
  }
  self.mood.reclassify(mood_id, kind)
  for sink in self.sinks {
    sink.on_entry(entry)
  }
}

///|
/// 束の時間窓を過ぎた判定結果を捨てる。
/// 判定待ちのまま窓を過ぎた束も外す（待っている先頭と後続は Pending が持っているので、判定が返れば配られる）。
/// 外したあとに来た同じコメントは、古い先頭を待たずにあらためて判定に回る。
fn Engine::forget_stale_verdicts(self : Engine, now : Int64) -> Unit {
  let oldest = now - self.config.bundle.window_ms
  let stale : Array[String] = []
  for key, verdict in self.verdicts {
    let last = if verdict.decided is None {
      verdict.created_at
    } else {
      verdict.touched_at
    }
    if last < oldest {
      stale.push(key)
    }
  }
  for key in stale {
    self.verdicts.remove(key)
  }
}

///|
/// LLM が書いた「いまの空気」の一文を覚える。
pub fn Engine::set_summary(self : Engine, text : String, now : Int64) -> Unit {
  self.llm_summary = Some((text, now))
}

///|
/// 拾い上げを既読にする。
pub fn Engine::dismiss(self : Engine, pickup_id : Int) -> Bool {
  self.pickup.dismiss(pickup_id)
}

///|
/// ダッシュボードに渡す全状態。期限切れ（束の窓、拾い上げの TTL）はここで反映される。
pub fn Engine::state(
  self : Engine,
  now : Int64,
  flow_limit? : Int = 100,
) -> EngineState {
  let newest_first = self.flow.rev()
  let state : EngineState = {
    now,
    context: self.config.context,
    pickups: self.pickup.view(now),
    bundles: self.bundler.summaries(now),
    mood_short: self.mood.snapshot(now, MOOD_SHORT_WINDOW_MS),
    mood_long: self.mood.snapshot(now, MOOD_LONG_WINDOW_MS),
    flow: if newest_first.length() > flow_limit {
      newest_first[:flow_limit].to_owned()
    } else {
      newest_first
    },
    stats: {
      received: self.received,
      early: self.early,
      inherited: self.inherited,
      sent: self.sent,
      judged: self.judged,
      failed: self.failed,
      dropped: self.dropped,
      queue_length: self.queue.length(),
      queue_limit: self.config.queue_limit,
      in_flight: self.in_flight,
      judge_delay_ms: self.judge_delay_ms,
    },
    summary: { text: "", source: "template", at: now, },
  }
  // LLM の一文が新しければそれを、無いか古ければテンプレートの一文を載せる
  let summary : Summary = match self.llm_summary {
    Some((text, at)) if now - at < SUMMARY_STALE_MS =>
      { text, source: "llm", at, }
    _ => { text: template_summary(state), source: "template", at: now, }
  }
  { ..state, summary, }
}
