///|
/// OPENAI_BASE_URL が無いときの既定。
pub const DEFAULT_BASE_URL : String = "https://api.openai.com/v1"

///|
/// OpenAI chat/completions のクライアント。「いまの空気」の一文を書くためだけに使う。
/// tool use は OpenAI の無料枠（データ共有）対象外なので使わない。
pub struct OpenAiClient {
  base_url : String
  api_key : String
  model : String
  /// モデルが reasoning_effort を拒否したら None にして以降送らない
  mut reasoning_effort : String?
}

///|
pub fn OpenAiClient::new(
  api_key~ : String,
  model? : String = @lib.DEFAULT_OPENAI_MODEL,
  base_url? : String = DEFAULT_BASE_URL,
) -> OpenAiClient {
  {
    base_url: base_url.trim_end(chars="/").to_owned(),
    api_key,
    model,
    reasoning_effort: Some(@lib.DEFAULT_REASONING_EFFORT),
  }
}

///|
/// 環境変数 OPENAI_API_KEY / OPENAI_MODEL / OPENAI_BASE_URL から作る。キーが無ければ None。
pub fn OpenAiClient::from_env() -> OpenAiClient? {
  guard @env.get_env_var("OPENAI_API_KEY") is Some(api_key) &&
    !api_key.is_empty() else {
    return None
  }
  Some(
    OpenAiClient::new(
      api_key~,
      model=@env.get_env_var("OPENAI_MODEL").unwrap_or(
        @lib.DEFAULT_OPENAI_MODEL,
      ),
      base_url=@env.get_env_var("OPENAI_BASE_URL").unwrap_or(DEFAULT_BASE_URL),
    ),
  )
}

///|
pub fn OpenAiClient::model(self : OpenAiClient) -> String {
  self.model
}

///|
/// system と user を送って応答本文を返す。
/// モデルが reasoning_effort を拒否したら候補を落として送り直す（minimal → none → 送らない）。
pub async fn OpenAiClient::chat(
  self : OpenAiClient,
  system : String,
  user : String,
) -> String {
  let messages : Array[@lib.Message] = [
    { role: System, content: system, },
    { role: User, content: user, },
  ]
  // 拒否されるたびに候補を落として送り直す（minimal → none → 送らない）
  let mut result : String? = None
  while result is None {
    result = Some(
      self.chat_once(messages) catch {
        @lib.OpenAiError::BadRequest(..) as err if err.is_unsupported_parameter(
            "reasoning_effort",
          ) &&
          self.reasoning_effort is Some(_) => {
          self.reasoning_effort = @lib.next_reasoning_effort(
            self.reasoning_effort,
          )
          continue
        }
        err => raise err
      },
    )
  }
  result.unwrap()
}

///|
async fn OpenAiClient::chat_once(
  self : OpenAiClient,
  messages : Array[@lib.Message],
) -> String {
  let body = @lib.build_chat_request(
    self.model,
    messages,
    max_completion_tokens=200,
    reasoning_effort=self.reasoning_effort,
  )
  let headers : @http.Headers = Map::from_array([
    (@http.CaseInsensitiveString("Authorization"), "Bearer \{self.api_key}"),
    (@http.CaseInsensitiveString("Content-Type"), "application/json"),
  ])
  let (response, data) = @http.post(
    "\{self.base_url}/chat/completions",
    body.stringify(),
    headers~,
  )
  @lib.parse_chat_response(response.code, data.text())
}

///|
/// runtime に注入する要約関数の形にする。
pub fn OpenAiClient::summarize_fn(
  self : OpenAiClient,
) -> async (String, String) -> String {
  (system, user) => self.chat(system, user)
}
