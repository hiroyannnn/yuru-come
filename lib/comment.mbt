///|
/// Source が供給する 1 コメント。
pub(all) struct Comment {
  /// Source ごとにプレフィックスを付けた参加者 ID（例: `twitch:12345`）
  participant_id : String
  /// 画面に出す投稿者名（不明なら空）
  author : String
  /// コメント本文（原文のまま）
  text : String
  /// 到着時刻（UNIX ミリ秒。不明なら 0）
  at : Int64
  /// 本文に含まれるスタンプ名（Twitch のエモート名など）。正規化でトークンとして保持する
  emotes : Array[String]
  /// コメントが書かれたチャンネル（Twitch のチャンネル名、YouTube の動画 ID）。不明なら空
  channel : String
} derive(Debug, Eq, ToJson)

///|
pub fn Comment::new(
  participant_id : String,
  text : String,
  author? : String = "",
  at? : Int64 = 0,
  emotes? : Array[String] = [],
  channel? : String = "",
) -> Comment {
  { participant_id, author, text, at, emotes, channel, }
}

///|
/// 参加者 ID を作る。Source 名をプレフィックスにして、Source 間で衝突しないようにする。
pub fn participant_id(source : String, id : String) -> String {
  "\{source}:\{id}"
}

///|
/// 参加者 ID のプレフィックス（`twitch` / `youtube` / `stdin` / `replay`）。
pub fn Comment::platform(self : Comment) -> String {
  match self.participant_id.find(":") {
    Some(i) => self.participant_id[:i].to_owned()
    None => ""
  }
}
