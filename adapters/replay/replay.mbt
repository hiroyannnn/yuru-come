///|
/// `時刻ms<TAB>参加者ID<TAB>発言` の TSV ログを `speed` 倍速で再生する Source。
/// 高流速のテストと開発用。ログを最後まで流したら終わる。
pub struct ReplaySource {
  path : String
  speed : Double
}

///|
pub fn ReplaySource::new(path : String, speed? : Double = 1.0) -> ReplaySource {
  { path, speed, }
}

///|
pub impl @lib.ChatSource for ReplaySource with fn run(self, submit) {
  let text = @fs.read_file(self.path).text() catch {
    err => {
      @runtime.log("replay: \{self.path} を読めません: \{err}")
      return
    }
  }
  @runtime.log(
    "replay: \{self.path} を \{self.speed} 倍速で再生します",
  )
  let started = @async.now()
  let mut first_ms : Int64? = None
  let mut count = 0
  for line in text.split("\n") {
    guard @lib.parse_replay_line(line.to_owned()) is Some((at_ms, comment)) else {
      continue
    }
    let origin = match first_ms {
      Some(origin) => origin
      None => {
        first_ms = Some(at_ms)
        at_ms
      }
    }
    // 行ごとの待ち時間を足していくと誤差が積もるので、再生開始からの経過時間で合わせる
    let due = started +
      @lib.replay_delay_ms(origin, at_ms, self.speed).to_int64()
    let wait = (due - @async.now()).to_int()
    if wait > 0 {
      @async.sleep(wait)
    }
    submit(comment)
    count += 1
  }
  @runtime.log(
    "replay: \{count} 件を \{@async.now() - started}ms で流し終えました",
  )
}
