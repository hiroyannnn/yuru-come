///|
pub(all) struct PickupConfig {
  /// この priority 以上なら種類によらず拾う
  priority_threshold : Double
  /// 拾ってからこの時間がたつと薄く表示する（ミリ秒）
  fade_ms : Int64
  /// 拾ってからこの時間がたつと消える（ミリ秒）
  expire_ms : Int64
} derive(Debug)

///|
pub fn PickupConfig::new(
  priority_threshold? : Double = 1.5,
  fade_ms? : Int64 = 300_000,
  expire_ms? : Int64 = 600_000,
) -> PickupConfig {
  { priority_threshold, fade_ms, expire_ms, }
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
}

///|
pub fn PickupList::new(
  config? : PickupConfig = PickupConfig::new(),
) -> PickupList {
  { config, items: [], next_id: 1, }
}

///|
/// 拾うべきコメントか。
///
/// - question / request / correction / first_time / trouble は priority によらず拾う
/// - それ以外は priority が閾値以上なら拾う
/// - abuse と、Jev が判定していないもの（reaction / 未判定）は拾わない
pub fn PickupConfig::should_pick_up(
  self : PickupConfig,
  kind : Kind,
  priority : Double,
) -> Bool {
  match kind {
    Question | Request | Correction | FirstTime | Trouble => true
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
  let id = self.next_id
  self.next_id += 1
  self.items.push({ id, comment, kind, priority, at: now, count: 1, })
  Some(id)
}

///|
/// 同じコメントが重ねて来たときに件数を増やす。既読・期限切れの ID なら何もしない。
pub fn PickupList::bump(self : PickupList, id : Int) -> Unit {
  for item in self.items {
    if item.id == id {
      item.count += 1
      return
    }
  }
}

///|
/// 既読にして消す。該当する項目があれば true。
pub fn PickupList::dismiss(self : PickupList, id : Int) -> Bool {
  let before = self.items.length()
  self.items = self.items.filter(item => item.id != id)
  self.items.length() < before
}

///|
/// 期限切れを捨てる。
pub fn PickupList::prune(self : PickupList, now : Int64) -> Unit {
  self.items = self.items.filter(item => now - item.at < self.config.expire_ms)
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
