///|
/// ターミナル Sink 用。拾い上げに新しく入ったコメントを 1 行にする。
/// 拾い上げに入らなかったもの、既にある項目に相乗りしただけのものは None。
pub fn render_pickup_line(entry : FlowEntry) -> String? {
  guard entry.pickup_id is Some(_) && entry.status is Judged else {
    return None
  }
  let priority = match entry.priority {
    Some(p) => " \{format_tenths(p)}"
    None => ""
  }
  let mark = if entry.kind is Trouble { "!! " } else { "" }
  let comment = entry.comment
  Some(
    "\{mark}[\{entry.kind.label()}\{priority}] \{comment.platform()}/\{comment.author}: \{comment.text}",
  )
}

///|
/// 小数第 1 位まで（四捨五入）。
fn format_tenths(value : Double) -> String {
  let tenths = (value * 10.0 + 0.5).floor().to_int()
  "\{tenths / 10}.\{tenths % 10}"
}
