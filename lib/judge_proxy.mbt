///|
/// 中継（運営者の Jev を使う Worker）が受け取るリクエスト。
/// 受け取るのはコメントと配信の文脈だけで、Jev への質問は中継側が `build_request` で組む。
/// 任意の質問を通さないので、「無料の Jev」として悪用されにくい。
pub(all) struct JudgeRequest {
  comment : String
  context : String
} derive(Debug, Eq)

///|
pub(all) suberror JudgeRequestError {
  MissingComment
  /// 長すぎるフィールド名
  TooLong(String)
} derive(Debug, Eq)

///|
/// コメントの最大文字数（Twitch の上限 500 字に合わせる）。
pub const JUDGE_MAX_COMMENT_CHARS : Int = 500

///|
/// 文脈の最大文字数。
pub const JUDGE_MAX_CONTEXT_CHARS : Int = 200

///|
pub fn parse_judge_request(json : Json) -> JudgeRequest raise JudgeRequestError {
  guard json is Object(fields) &&
    fields.get("comment") is Some(String(comment)) &&
    !comment.trim(chars=" \t\r\n　").is_empty() else {
    raise MissingComment
  }
  if comment.char_length() > JUDGE_MAX_COMMENT_CHARS {
    raise TooLong("comment")
  }
  let context = match fields.get("context") {
    Some(String(c)) => c
    _ => ""
  }
  if context.char_length() > JUDGE_MAX_CONTEXT_CHARS {
    raise TooLong("context")
  }
  { comment, context, }
}
