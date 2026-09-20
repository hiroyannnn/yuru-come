///|
/// 拾うべきコメントだけを 1 行ずつ標準出力に出す Sink（デバッグと最小構成用）。
pub struct TerminalSink {
  /// 出力した行数
  mut printed : Int
}

///|
pub fn TerminalSink::new() -> TerminalSink {
  { printed: 0, }
}

///|
pub impl @lib.Sink for TerminalSink with fn on_entry(self, entry) {
  if @lib.render_pickup_line(entry) is Some(line) {
    self.printed += 1
    println(line)
  }
}
