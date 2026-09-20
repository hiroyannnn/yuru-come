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
pub(all) struct Pending {
  entry_id : Int
  comment : Comment
  /// 束のキー（相乗りの判定結果を引くのに使う）
  bundle_key : String
  /// この束の先頭として判定結果を束に残すか
  leads_bundle : Bool
  /// 正規化後の文字数（落とす候補を選ぶのに使う）
  length : Int
} derive(Debug, Eq)

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
struct BundleVerdict {
  /// 先頭のコメントの判定結果。None は判定待ち
  mut decided : (Kind, Double?)?
  mut pickup_id : Int?
  /// 先頭の判定を待っている後続（流れの項目 ID）
  followers : Array[Int]
  /// 最後に触った時刻。束の時間窓を過ぎたら捨てる
  mut touched_at : Int64
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
  /// 流れの項目 ID → 空気の記録 ID（判定後に種類を付け替える）
  mood_ids : Map[Int, Int]
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
    mood_ids: Map([]),
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
    let removed = self.flow.remove(0)
    self.mood_ids.remove(removed.id)
  }
  let label = comment.text.trim(chars=" \t\r\n\u3000").to_owned()
  self.mood_ids[entry.id] = self.mood.record(
    now,
    comment.participant_id,
    Unjudged,
    reaction=hit.key,
    label~,
  )
  if self.rules.is_reaction(comment.text, emotes=comment.emotes) {
    self.early += 1
    if !self.verdicts.contains(hit.key) {
      self.verdicts[hit.key] = {
        decided: Some((Reaction, None)),
        pickup_id: None,
        followers: [],
        touched_at: now,
      }
    }
    return self.settle(entry, Reaction, None, Early)
  }
  match self.verdicts.get(hit.key) {
    Some({ decided: Some((kind, priority)), .. } as verdict) if !(kind
      is Unjudged) &&
      (hit.exact || !is_pickup_kind(kind)) => {
      verdict.touched_at = now
      self.inherited += 1
      self.follow(entry, verdict, kind, priority)
    }
    Some({ decided: None, .. } as verdict) if hit.exact => {
      verdict.touched_at = now
      verdict.followers.push(entry.id)
    }
    existing => {
      // 束の先頭（または先頭が未判定に終わった束の仕切り直し）なら、判定結果を束に残す
      let leads_bundle = existing
        is (None | Some({ decided: Some((Unjudged, _)), .. }))
      if leads_bundle {
        self.verdicts[hit.key] = {
          decided: None,
          pickup_id: None,
          followers: [],
          touched_at: now,
        }
      }
      self.queue.push({
        entry_id: entry.id,
        comment,
        bundle_key: hit.key,
        leads_bundle,
        length: key.char_length(),
      })
      self.shed_overflow()
    }
  }
}

///|
/// 配信者が拾うべき種類か（類似度だけで束に入ったコメントを相乗りさせない種類）。
fn is_pickup_kind(kind : Kind) -> Bool {
  kind is (Question | Request | Correction | FirstTime | Trouble)
}

///|
/// キューが上限を超えていたら、古い半分のうちいちばん短いコメントを未判定のまま流す。
fn Engine::shed_overflow(self : Engine) -> Unit {
  while self.queue.length() > self.config.queue_limit {
    let older_half = (self.queue.length() + 1) / 2
    let mut victim = 0
    for i in 1..<older_half {
      if self.queue[i].length < self.queue[victim].length {
        victim = i
      }
    }
    let pending = self.queue.remove(victim)
    self.resolve(pending, Unjudged, None, Dropped)
  }
}

///|
/// 次に判定するコメントを取り出す。無ければ None。
pub fn Engine::take_next(self : Engine) -> Pending? {
  guard self.queue.length() > 0 else { return None }
  self.sent += 1
  self.in_flight += 1
  Some(self.queue.remove(0))
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
  let entry = self.find_entry(pending.entry_id)
  let pickup_id = match (now, priority) {
    (Some(now), Some(priority)) =>
      self.pickup.offer(pending.comment, kind, priority, now)
    _ => None
  }
  if entry is Some(entry) {
    entry.pickup_id = pickup_id
    self.settle(entry, kind, priority, status)
  }
  guard pending.leads_bundle &&
    self.verdicts.get(pending.bundle_key) is Some(verdict) else {
    return
  }
  verdict.decided = Some((kind, priority))
  verdict.pickup_id = pickup_id
  if now is Some(now) {
    verdict.touched_at = now
  }
  for follower_id in verdict.followers {
    guard self.find_entry(follower_id) is Some(follower) else { continue }
    if kind is Unjudged {
      // 先頭が未判定に終わったら、相乗り待ちも同じ扱いで流れにだけ出す
      self.settle(follower, Unjudged, None, status)
    } else {
      self.inherited += 1
      self.follow(follower, verdict, kind, priority)
    }
  }
  verdict.followers.clear()
}

///|
/// 束の先頭の判定に相乗りさせる。先頭が拾い上げに入っていれば、その件数を増やす。
fn Engine::follow(
  self : Engine,
  entry : FlowEntry,
  verdict : BundleVerdict,
  kind : Kind,
  priority : Double?,
) -> Unit {
  if verdict.pickup_id is Some(id) {
    self.pickup.bump(id)
    entry.pickup_id = Some(id)
  }
  self.settle(entry, kind, priority, Inherited)
}

///|
/// 流れの項目の種類を確定し、空気に反映して Sink に通知する。
fn Engine::settle(
  self : Engine,
  entry : FlowEntry,
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
  if self.mood_ids.get(entry.id) is Some(mood_id) {
    self.mood.reclassify(mood_id, kind)
  }
  for sink in self.sinks {
    sink.on_entry(entry)
  }
}

///|
fn Engine::find_entry(self : Engine, id : Int) -> FlowEntry? {
  // 新しい項目ほど後ろにあるので、後ろから探す
  for i = self.flow.length() - 1; i >= 0; i = i - 1 {
    if self.flow[i].id == id {
      return Some(self.flow[i])
    }
  }
  None
}

///|
/// 束の時間窓を過ぎた判定結果を捨てる。判定待ちのものは残す。
fn Engine::forget_stale_verdicts(self : Engine, now : Int64) -> Unit {
  let oldest = now - self.config.bundle.window_ms
  let stale : Array[String] = []
  for key, verdict in self.verdicts {
    if verdict.decided is Some(_) && verdict.touched_at < oldest {
      stale.push(key)
    }
  }
  for key in stale {
    self.verdicts.remove(key)
  }
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
  {
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
    },
  }
}
