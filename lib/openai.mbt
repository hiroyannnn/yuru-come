///|
/// chat/completions のメッセージの役割。
pub(all) enum Role {
  System
  User
} derive(Debug, Eq)

///|
pub(all) struct Message {
  role : Role
  content : String
} derive(Debug, Eq)

///|
/// OpenAI の messages 要素の形 `{"role": ..., "content": ...}`。
pub impl ToJson for Message with fn to_json(self) {
  {
    "role": match self.role {
      System => "system"
      User => "user"
    },
    "content": self.content,
  }
}

///|
/// OPENAI_MODEL が無いときの既定モデル。
pub const DEFAULT_OPENAI_MODEL : String = "gpt-5-mini"

///|
pub const DEFAULT_MAX_COMPLETION_TOKENS : Int = 1024

///|
/// 速度優先の既定 reasoning_effort。
pub const DEFAULT_REASONING_EFFORT : String = "minimal"

///|
/// OpenAI chat/completions の呼び出しで起きるエラー。
pub(all) suberror OpenAiError {
  /// 401
  Unauthorized(String)
  /// 429
  RateLimited(String)
  /// 5xx
  ServerError(code~ : Int, message~ : String)
  /// 上記以外の 4xx
  BadRequest(code~ : Int, message~ : String)
  /// 2xx だが本文が JSON ではない
  InvalidJson(String)
  /// 2xx だが choices[0].message.content が無い
  MissingContent(String)
} derive(Debug, Eq)

///|
pub impl Show for OpenAiError with fn output(self, logger) {
  let message = match self {
    Unauthorized(detail) =>
      "OpenAI の認証に失敗しました（401）: \{detail}"
    RateLimited(detail) =>
      "OpenAI のレート制限に達しました（429）: \{detail}"
    ServerError(code~, message~) =>
      "OpenAI がサーバエラーを返しました（\{code}）: \{message}"
    BadRequest(code~, message~) =>
      "OpenAI がリクエストを拒否しました（\{code}）: \{message}"
    InvalidJson(detail) =>
      "OpenAI の応答を JSON として解析できません: \{detail}"
    MissingContent(detail) =>
      "OpenAI の応答に本文がありません: \{detail}"
  }
  logger.write_string(message)
}

///|
/// 「そのパラメータはこのモデルでは使えない」という 400 かどうか。
/// reasoning_effort をモデルが拒否したときに外して再送する判断に使う。
pub fn OpenAiError::is_unsupported_parameter(
  self : OpenAiError,
  parameter : String,
) -> Bool {
  match self {
    BadRequest(code=400, message~) =>
      message.contains("Unsupported parameter") &&
      message.contains("'\{parameter}'")
    _ => false
  }
}

///|
/// `POST /v1/chat/completions` のボディ。gpt-5 系は temperature 非対応なので送らない。
pub fn build_chat_request(
  model : String,
  messages : Array[Message],
  max_completion_tokens? : Int = DEFAULT_MAX_COMPLETION_TOKENS,
  reasoning_effort? : String? = Some(DEFAULT_REASONING_EFFORT),
) -> Json {
  let body : Map[String, Json] = {
    "model": Json::string(model),
    "messages": Json::array(messages.map(m => m.to_json())),
    "max_completion_tokens": Json::number(max_completion_tokens.to_double()),
  }
  if reasoning_effort is Some(effort) {
    body["reasoning_effort"] = Json::string(effort)
  }
  Json::object(body)
}

///|
/// HTTP ステータスと本文から応答本文（choices[0].message.content）を取り出す。
/// 2xx 以外はステータスに応じた OpenAiError にする。
pub fn parse_chat_response(
  status : Int,
  body : String,
) -> String raise OpenAiError {
  if status < 200 || status >= 300 {
    let message = error_message(body)
    match status {
      401 => raise Unauthorized(message)
      429 => raise RateLimited(message)
      code if code >= 500 => raise ServerError(code~, message~)
      code => raise BadRequest(code~, message~)
    }
  }
  let json = @json.parse(body) catch {
    err => raise InvalidJson(err.to_string())
  }
  match json {
    Object(
      {
        "choices": Array(
          [
            Object(
              { "message": Object({ "content": String(content), .. }), .. }
            ),
            ..,
          ]
        ),
        ..
      }
    ) => content
    Object({ "choices": Array([_, ..]), .. }) =>
      raise MissingContent(
        "choices[0].message.content が文字列ではありません",
      )
    _ => raise MissingContent("choices が空です")
  }
}

///|
/// エラー本文の `error.message` を取り出す。JSON でなければ本文そのまま。
fn error_message(body : String) -> String {
  let json = @json.parse(body) catch { _ => return body }
  match json {
    Object({ "error": Object({ "message": String(message), .. }), .. }) =>
      message
    _ => body
  }
}
