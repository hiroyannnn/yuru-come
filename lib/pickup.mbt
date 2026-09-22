///|
pub(all) struct PickupConfig {
  /// この priority 以上なら種類によらず拾う
  priority_threshold : Double
  /// 拾うべき種類（trouble / question / request / correction / first_time）に求める priority の下限。
  /// 視聴者どうしの掛け合いが質問やリクエストと判定されても、ゲーム内の嘆きが trouble と判定されても、
  /// Jev が「拾わなくてよい」と見ていれば拾わない
  kind_floor : Double
  /// 拾ってからこの時間がたつと薄く表示する（ミリ秒）
  fade_ms : Int64
  /// 拾ってからこの時間がたつと消える（ミリ秒）
  expire_ms : Int64
} derive(Debug)

///|
pub fn PickupConfig::new(
  priority_threshold? : Double = 1.5,
  kind_floor? : Double = 0.6,
  fade_ms? : Int64 = 300_000,
  expire_ms? : Int64 = 600_000,
) -> PickupConfig {
  { priority_threshold, kind_floor, fade_ms, expire_ms, }
}

///|
/// 画面に出す拾い上げ 1 件。
pub(all) struct PickupView {
  id : Int
  comment : Comment
  kind : Kind
  priority : Double
  /// 拾い上げた時刻
  at : Int64
  /// 同じコメントが重ねて来た件数（最初の 1 件を含む）
  count : Int
  /// TTL の前半を過ぎて薄く表示する
  faded : Bool
  /// 最上位に固定する（trouble）
  pinned : Bool
} derive(Debug, Eq, ToJson)

///|
struct PickupItem {
  id : Int
  comment : Comment
  kind : Kind
  priority : Double
  at : Int64
  mut count : Int
}

///|
/// 配信者が拾うべきコメントのリスト。
pub struct PickupList {
  config : PickupConfig
  mut items : Array[PickupItem]
  mut next_id : Int
  /// まだ取り出されていない正解データ
  labels : Array[PickupLabel]
}

///|
pub fn PickupList::new(
  config? : PickupConfig = PickupConfig::new(),
) -> PickupList {
  { config, items: [], next_id: 1, labels: [], }
}

///|
/// 拾うべきコメントか。
///
/// - trouble / question / request / correction / first_time は priority が下限（kind_floor）以上なら拾う
/// - それ以外は priority が閾値（priority_threshold）以上なら拾う
/// - abuse と、Jev が判定していないもの（reaction / 未判定）は拾わない
pub fn PickupConfig::should_pick_up(
  self : PickupConfig,
  kind : Kind,
  priority : Double,
) -> Bool {
  match kind {
    Trouble | Question | Request | Correction | FirstTime =>
      priority >= self.kind_floor
    Abuse | Reaction | Unjudged => false
    Feedback | Greeting | Chatter => priority >= self.priority_threshold
  }
}

///|
/// 仕分け済みのコメントを見せ、拾うべきならリストに入れて項目 ID を返す。
pub fn PickupList::offer(
  self : PickupList,
  comment : Comment,
  kind : Kind,
  priority : Double,
  now : Int64,
) -> Int? {
  guard self.config.should_pick_up(kind, priority) else { return None }
  // 画面（view）を見ない構成でも溜まり続けないよう、足す前に期限切れを捨てる
  self.prune(now)
  let id = self.next_id
  self.next_id += 1
  self.items.push({ id, comment, kind, priority, at: now, count: 1, })
  Some(id)
}

///|
/// 同じコメントが重ねて来たときに件数を増やす。既読・期限切れの ID なら何もせず false。
pub fn PickupList::bump(self : PickupList, id : Int) -> Bool {
  for item in self.items {
    if item.id == id {
      item.count += 1
      return true
    }
  }
  false
}

///|
/// 既読にして消す（「拾った」として記録する）。該当する項目があれば true。
pub fn PickupList::dismiss(
  self : PickupList,
  id : Int,
  now? : Int64 = 0,
) -> Bool {
  self.resolve(id, Picked, now)
}

///|
/// 期限切れを捨てる（「期限切れ」として記録する）。
pub fn PickupList::prune(self : PickupList, now : Int64) -> Unit {
  let kept : Array[PickupItem] = []
  for item in self.items {
    if now - item.at < self.config.expire_ms {
      kept.push(item)
    } else {
      self.record(item, Expired, now)
    }
  }
  self.items = kept
}

///|
fn PickupList::record(
  self : PickupList,
  item : PickupItem,
  outcome : PickupOutcome,
  now : Int64,
) -> Unit {
  self.labels.push({
    comment: item.comment,
    kind: item.kind,
    priority: item.priority,
    offered_at: item.at,
    resolved_at: now,
    outcome,
  })
}

///|
/// 表示順の一覧。trouble を最上位に固定し、priority の高い順、同じなら新しい順。
pub fn PickupList::view(self : PickupList, now : Int64) -> Array[PickupView] {
  self.prune(now)
  let views : Array[PickupView] = self.items.map(item => {
    id: item.id,
    comment: item.comment,
    kind: item.kind,
    priority: item.priority,
    at: item.at,
    count: item.count,
    faded: now - item.at >= self.config.fade_ms,
    pinned: item.kind is Trouble,
  })
  views.sort_by((a, b) => {
    if a.pinned != b.pinned {
      b.pinned.compare(a.pinned)
    } else if a.priority != b.priority {
      b.priority.compare(a.priority)
    } else if a.at != b.at {
      b.at.compare(a.at)
    } else {
      b.id.compare(a.id)
    }
  })
  views
}

///|
/// 保持している項目の数（期限切れを含む）。
pub fn PickupList::size(self : PickupList) -> Int {
  self.items.length()
}

///|
/// 配信者が気になるコメントをどうしたか。
pub(all) enum PickupOutcome {
  /// カードをクリックした（拾った）
  Picked
  /// × でスルーした
  Skipped
  /// 何もしないまま期限切れで消えた
  Expired
} derive(Debug, Eq)

///|
pub impl ToJson for PickupOutcome with fn to_json(self) {
  Json::string(
    match self {
      Picked => "picked"
      Skipped => "skipped"
      Expired => "expired"
    },
  )
}

///|
/// 正解データ 1 件。仕分けの評価や学習に使う。
pub(all) struct PickupLabel {
  comment : Comment
  kind : Kind
  priority : Double
  offered_at : Int64
  resolved_at : Int64
  outcome : PickupOutcome
} derive(Debug, Eq, ToJson)

///|
/// 配信者の操作（拾った・スルー）で項目を消し、記録する。該当する項目があれば true。
pub fn PickupList::resolve(
  self : PickupList,
  id : Int,
  outcome : PickupOutcome,
  now : Int64,
) -> Bool {
  let kept : Array[PickupItem] = []
  let mut found = false
  for item in self.items {
    if item.id == id {
      found = true
      self.record(item, outcome, now)
    } else {
      kept.push(item)
    }
  }
  self.items = kept
  found
}

///|
/// 溜まった正解データを取り出して空にする。
pub fn PickupList::take_labels(self : PickupList) -> Array[PickupLabel] {
  let labels = self.labels.copy()
  self.labels.clear()
  labels
}
