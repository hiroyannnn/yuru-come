///|
/// Twitch IRC から読んだ 1 行の解釈結果。
pub(all) enum IrcMessage {
  /// サーバからの PING。payload をそのまま PONG で返す
  Ping(String)
  /// チャット発言
  Chat(Comment)
  /// それ以外（接続時の挨拶など）
  Other(String)
} derive(Debug, Eq)

///|
/// 匿名ユーザーで読み取り専用接続するためのログイン行。
/// `twitch.tv/tags` を要求して user-id・表示名・エモートの位置・送信時刻を受け取る。
pub fn twitch_login_lines(nick : String, channel : String) -> Array[String] {
  ["CAP REQ :twitch.tv/tags", "NICK \{nick}", "JOIN #\{channel.to_lower()}"]
}

///|
/// PING への返答行。
pub fn pong_line(payload : String) -> String {
  "PONG :\{payload}"
}

///|
/// IRC の 1 行（`[@tags] [:prefix] COMMAND [params] [:trailing]`）を解釈する。
pub fn parse_irc_line(raw : String) -> IrcMessage {
  let line = raw.trim(chars="\r\n").to_owned()
  let mut rest = line.view()
  let tags = if rest is ['@', .. after_at] {
    let (tag_part, after) = split_once(after_at, ' ')
    rest = after
    parse_tags(tag_part)
  } else {
    Map([])
  }
  let prefix = if rest is [':', .. after_colon] {
    let (p, after) = split_once(after_colon, ' ')
    rest = after
    p.to_owned()
  } else {
    ""
  }
  let (command, params) = split_once(rest, ' ')
  match command {
    "PING" => Ping(trailing_of(params))
    "PRIVMSG" => {
      let text = trailing_of(params)
      let id = match tags.get("user-id") {
        Some(user_id) if !user_id.is_empty() => user_id
        _ => nick_of(prefix)
      }
      let at = match tags.get("tmi-sent-ts") {
        Some(ts) => parse_int64(ts)
        None => 0
      }
      let author = match tags.get("display-name") {
        Some(name) if !name.is_empty() => name
        _ => nick_of(prefix)
      }
      let emotes = match tags.get("emotes") {
        Some(tag) => emote_names(text, tag)
        None => []
      }
      Chat({
        participant_id: participant_id("twitch", id),
        author,
        text,
        at,
        emotes,
      })
    }
    _ => Other(line)
  }
}

///|
/// `sep` で最初の 1 回だけ分割する。見つからなければ残りは空。
fn split_once(s : StringView, sep : Char) -> (StringView, StringView) {
  match s.find(sep.to_string()) {
    Some(i) => (s[:i], s[i + 1:])
    None => (s, "")
  }
}

///|
/// params の `:` 以降（trailing）を取り出す。無ければ params 全体。
fn trailing_of(params : StringView) -> String {
  match params.find(":") {
    Some(i) => params[i + 1:].to_owned()
    None => params.to_owned()
  }
}

///|
/// `nick!user@host` から nick を取り出す。
fn nick_of(prefix : String) -> String {
  match prefix.find("!") {
    Some(i) => prefix[:i].to_owned()
    None => prefix
  }
}

///|
fn parse_tags(part : StringView) -> Map[String, String] {
  let tags : Map[String, String] = Map([])
  for pair in part.split(";") {
    let (key, value) = split_once(pair, '=')
    tags[key.to_owned()] = value.to_owned()
  }
  tags
}

///|
fn parse_int64(s : String) -> Int64 {
  let mut n : Int64 = 0
  for c in s {
    guard c is ('0'..='9') else { return 0 }
    n = n * 10 + (c.to_int() - '0').to_int64()
  }
  n
}

///|
/// `emotes` タグ（`<id>:<開始>-<終了>,.../<id>:...`、位置は文字単位）から、本文中のエモート名を取り出す。
/// 重複は除く。壊れた範囲は無視する。
fn emote_names(text : String, tag : String) -> Array[String] {
  let chars = text.to_array()
  let names : Array[String] = []
  for emote in tag.split("/") {
    let (_, ranges) = split_once(emote, ':')
    for range in ranges.split(",") {
      let (start_text, end_text) = split_once(range, '-')
      guard parse_index(start_text) is Some(start) &&
        parse_index(end_text) is Some(end) &&
        start <= end &&
        end < chars.length() else {
        continue
      }
      let name = StringBuilder()
      for i in start..<=end {
        name.write_char(chars[i])
      }
      let name = name.to_string()
      if !names.contains(name) {
        names.push(name)
      }
    }
  }
  names
}

///|
fn parse_index(s : StringView) -> Int? {
  guard s.length() > 0 && s.length() <= 9 else { return None }
  let mut n = 0
  for c in s {
    guard c is ('0'..='9') else { return None }
    n = n * 10 + (c.to_int() - '0')
  }
  Some(n)
}
