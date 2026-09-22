///|
/// replay ログの 1 行（`時刻ms<TAB>参加者ID<TAB>発言`）を、ログ上の時刻と Comment にする。
/// 空行、`#` で始まる行、形式に合わない行は None。Comment の `at` は再生時に付けるので 0 のまま。
pub fn parse_replay_line(line : String) -> (Int64, Comment)? {
  let line = line.trim(chars="\r\n").to_owned()
  guard !line.has_prefix("#") else { return None }
  guard line.find("\t") is Some(first) else { return None }
  let rest = line[first + 1:]
  guard rest.find("\t") is Some(second) else { return None }
  guard parse_millis(line[:first].trim(chars=" ")) is Some(at_ms) else {
    return None
  }
  let id = rest[:second].trim(chars=" ").to_owned()
  let text = rest[second + 1:].to_owned()
  guard !id.is_empty() && !text.trim(chars=" \t　").is_empty() else {
    return None
  }
  Some((at_ms, Comment::new(participant_id("replay", id), text, author=id)))
}

///|
fn parse_millis(s : StringView) -> Int64? {
  guard s.length() > 0 && s.length() <= 15 else { return None }
  let mut n : Int64 = 0
  for c in s {
    guard c is ('0'..='9') else { return None }
    n = n * 10 + (c.to_int() - '0').to_int64()
  }
  Some(n)
}

///|
/// 倍速再生で、前の行から次の行までに待つ時間（ミリ秒）。
pub fn replay_delay_ms(
  previous_ms : Int64,
  next_ms : Int64,
  speed : Double,
) -> Int {
  guard speed > 0.0 && next_ms > previous_ms else { return 0 }
  ((next_ms - previous_ms).to_double() / speed).to_int()
}
