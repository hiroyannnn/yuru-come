///|
/// 標準入力の 1 行（`参加者ID<TAB>発言`）を Comment にする。
/// TAB が無ければ匿名参加者（`stdin:<anonymous_id>`）の発言。空行は None。
/// `source` は ID のプレフィックス（外部ブリッジをパイプするときに `tiktok` などへ変える）。
pub fn parse_stdin_line(
  line : String,
  at~ : Int64,
  anonymous_id? : String = "anon",
  source? : String = "stdin",
) -> Comment? {
  let trimmed = line.trim(chars=" \t\r\n").to_owned()
  if trimmed.is_empty() {
    return None
  }
  let (id, text) = match trimmed.find("\t") {
    Some(i) =>
      (trimmed[:i].to_owned(), trimmed[i + 1:].trim(chars=" \t").to_owned())
    None => (anonymous_id, trimmed)
  }
  Some(Comment::new(participant_id(source, id), text, author=id, at~))
}
