///|
/// 上位の反応 1 件。
pub(all) struct ReactionCount {
  label : String
  count : Int
} derive(Debug, Eq, ToJson)

///|
/// ある時間窓の「いまの空気」。
pub(all) struct MoodSnapshot {
  window_ms : Int64
  total : Int
  /// 種類（Kind の key）ごとの件数。0 件の種類は入らない
  by_kind : Map[String, Int]
  /// コメント流速（件/秒）
  rate_per_sec : Double
  participants : Int
  /// 件数の多い順の反応（2 件以上）
  top_reactions : Array[ReactionCount]
} derive(Debug, ToJson)

///|
struct MoodEvent {
  id : Int
  at : Int64
  participant_id : String
  mut kind : Kind
  /// 反応をまとめるキー（束のキー）。反応でなければ None
  reaction : String?
  /// 反応の見出しに使う原文
  label : String
}

///|
/// スライディング窓で空気を集計する純粋データ構造。
pub struct Mood {
  retention_ms : Int64
  /// 古い順
  mut events : Array[MoodEvent]
  mut next_id : Int
}

///|
/// `retention_ms` は記録を保持する期間。いちばん長い窓（5 分）に合わせる。
pub fn Mood::new(retention_ms? : Int64 = 300_000) -> Mood {
  { retention_ms, events: [], next_id: 1, }
}

///|
/// コメント 1 件を記録し、あとで `reclassify` するための ID を返す。
pub fn Mood::record(
  self : Mood,
  at : Int64,
  participant_id : String,
  kind : Kind,
  reaction? : String,
  label? : String,
) -> Int {
  let id = self.next_id
  self.next_id += 1
  let label = label.unwrap_or(reaction.unwrap_or(""))
  self.events.push({ id, at, participant_id, kind, reaction, label, })
  self.prune(at)
  id
}

///|
/// 判定があとから決まったコメントの種類を付け替える。保持期間を過ぎていれば何もしない。
pub fn Mood::reclassify(self : Mood, id : Int, kind : Kind) -> Unit {
  for event in self.events {
    if event.id == id {
      event.kind = kind
      return
    }
  }
}

///|
/// 保持期間を過ぎた記録を捨てる。
pub fn Mood::prune(self : Mood, now : Int64) -> Unit {
  let oldest = now - self.retention_ms
  if self.events.length() > 0 && self.events[0].at < oldest {
    self.events = self.events.filter(event => event.at >= oldest)
  }
}

///|
pub fn Mood::size(self : Mood) -> Int {
  self.events.length()
}

///|
/// `now` から `window_ms` さかのぼった窓の集計。
pub fn Mood::snapshot(
  self : Mood,
  now : Int64,
  window_ms : Int64,
  top? : Int = 5,
) -> MoodSnapshot {
  let oldest = now - window_ms
  let by_kind : Map[String, Int] = Map([])
  let participants : Map[String, Unit] = Map([])
  let reactions : Map[String, ReactionCount] = Map([])
  let mut total = 0
  for event in self.events {
    guard event.at >= oldest && event.at <= now else { continue }
    total += 1
    let key = event.kind.key()
    by_kind[key] = by_kind.get(key).unwrap_or(0) + 1
    participants[event.participant_id] = ()
    guard event.kind is Reaction && event.reaction is Some(reaction) else {
      continue
    }
    reactions[reaction] = match reactions.get(reaction) {
      None => { label: event.label, count: 1, }
      Some(seen) =>
        {
          label: if event.label.char_length() < seen.label.char_length() {
            event.label
          } else {
            seen.label
          },
          count: seen.count + 1,
        }
    }
  }
  let top_reactions = reactions.values().filter(r => r.count >= 2).collect()
  top_reactions.sort_by((a, b) => b.count.compare(a.count))
  {
    window_ms,
    total,
    by_kind,
    rate_per_sec: total.to_double() * 1000.0 / window_ms.to_double(),
    participants: participants.length(),
    top_reactions: if top_reactions.length() > top {
      top_reactions[:top].to_owned()
    } else {
      top_reactions
    },
  }
}
