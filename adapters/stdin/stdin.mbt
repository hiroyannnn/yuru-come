///|
/// 標準入力から `参加者ID<TAB>発言` 行を読む Source。EOF で終わる。
/// 外部ブリッジ（tools/tiktok-bridge など）をパイプするときは `source` で ID のプレフィックスを変える。
pub struct StdinSource {
  /// 匿名参加者の ID に使う名前
  anonymous_id : String
  source : String
}

///|
pub fn StdinSource::new(
  anonymous_id? : String = "anon",
  source? : String = "stdin",
) -> StdinSource {
  { anonymous_id, source, }
}

///|
pub impl @lib.Source for StdinSource with fn run(self, submit) {
  while @stdio.stdin.read_until("\n") is Some(line) {
    guard @lib.parse_stdin_line(
        line,
        at=@async.now(),
        anonymous_id=self.anonymous_id,
        source=self.source,
      )
      is Some(comment) else {
      continue
    }
    submit(comment)
  }
}
