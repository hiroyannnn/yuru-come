///|
const DAY_MS : Int64 = 86_400_000

///|
/// UTC の 1 日あたり `limit` 回までを許す予算。運営者持ちの Jev の使いすぎを止める最後の砦。
/// 時刻は呼び出し側から渡すので純粋。Durable Object のストレージに dump / restore で置く。
pub struct DailyBudget {
  limit : Int
  mut day : Int64
  mut used : Int
}

///|
pub fn DailyBudget::new(limit~ : Int) -> DailyBudget {
  { limit, day: -1, used: 0, }
}

///|
fn DailyBudget::roll(self : DailyBudget, now_ms : Int64) -> Unit {
  let day = now_ms / DAY_MS
  if day != self.day {
    self.day = day
    self.used = 0
  }
}

///|
/// 1 回分を使う。上限に達していれば使わずに false。
pub fn DailyBudget::spend(self : DailyBudget, now_ms : Int64) -> Bool {
  self.roll(now_ms)
  if self.used >= self.limit {
    return false
  }
  self.used += 1
  true
}

///|
/// その日に使った回数。
pub fn DailyBudget::used(self : DailyBudget, now_ms : Int64) -> Int {
  self.roll(now_ms)
  self.used
}

///|
/// その日の残り回数。
pub fn DailyBudget::remaining(self : DailyBudget, now_ms : Int64) -> Int {
  let left = self.limit - self.used(now_ms)
  if left > 0 {
    left
  } else {
    0
  }
}

///|
pub fn DailyBudget::dump(self : DailyBudget) -> Json {
  { "day": self.day.to_double(), "used": self.used }
}

///|
/// 保存した状態から戻す。上限は今の設定を使う。壊れていれば空から始める。
pub fn DailyBudget::restore(json : Json, limit~ : Int) -> DailyBudget {
  match json {
    Object({ "day": Number(day, ..), "used": Number(used, ..), .. }) =>
      { limit, day: day.to_int64(), used: used.to_int(), }
    _ => DailyBudget::new(limit~)
  }
}
