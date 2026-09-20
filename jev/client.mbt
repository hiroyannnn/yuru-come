///|
/// JEV_URL が無いときの既定（ローカルの open-jev）。
pub const DEFAULT_URL : String = "http://127.0.0.1:8000"

///|
/// JEV_API_KEY が無いときの既定。
pub const DEFAULT_API_KEY : String = "local"

///|
pub suberror JevError {
  /// 200 以外のステータス（コード, 本文）
  HttpStatus(Int, String)
  /// 本文が JSON として壊れている
  InvalidJson(String)
  /// JSON だが期待した形ではない
  BadResponse(@lib.ResponseError)
} derive(Debug)

///|
/// TypeSafe Jev 互換 API（`POST /v1/systemone`）のクライアント。
pub struct JevClient {
  base_url : String
  api_key : String
  /// リクエストに載せるモデル名（JEV_MODEL。Vercel AI Gateway では `typesafe-ai/jev`）
  model : String
}

///|
pub fn JevClient::new(
  base_url? : String = DEFAULT_URL,
  api_key? : String = DEFAULT_API_KEY,
  model? : String = @lib.JEV_MODEL,
) -> JevClient {
  { base_url: base_url.trim_end(chars="/").to_owned(), api_key, model, }
}

///|
/// 環境変数 JEV_URL / JEV_API_KEY / JEV_MODEL から作る。
pub fn JevClient::from_env() -> JevClient {
  JevClient::new(
    base_url=@env.get_env_var("JEV_URL").unwrap_or(DEFAULT_URL),
    api_key=@env.get_env_var("JEV_API_KEY").unwrap_or(DEFAULT_API_KEY),
    model=@env.get_env_var("JEV_MODEL").unwrap_or(@lib.JEV_MODEL),
  )
}

///|
/// 再試行までの待ち（ミリ秒）。
const RETRY_DELAY_MS : Int = 300

///|
/// 1 コメントを仕分ける。kind と priority の 2 質問を 1 リクエストで送る。
/// 一時的な失敗（429 と 5xx。Vercel AI Gateway は数 % の割合で 504 を返す）は 1 回だけ再試行する。
pub async fn JevClient::judge(
  self : JevClient,
  context : String,
  comment : @lib.Comment,
) -> @lib.Triage {
  self.request(context, comment) catch {
    HttpStatus(code, _) if is_transient_status(code) => {
      @async.sleep(RETRY_DELAY_MS)
      self.request(context, comment)
    }
    err => raise err
  }
}

///|
async fn JevClient::request(
  self : JevClient,
  context : String,
  comment : @lib.Comment,
) -> @lib.Triage {
  let headers : @http.Headers = Map::from_array([
    (@http.CaseInsensitiveString("Authorization"), "Bearer \{self.api_key}"),
    (@http.CaseInsensitiveString("Content-Type"), "application/json"),
  ])
  let body = @lib.build_request(comment.text, context~, model=self.model).stringify()
  let (response, data) = @http.post(
    "\{self.base_url}/v1/systemone",
    body,
    headers~,
  )
  if response.code != 200 {
    raise HttpStatus(response.code, data.text())
  }
  let json = data.json() catch { err => raise InvalidJson(err.to_string()) }
  @lib.parse_response(json) catch {
    err => raise BadResponse(err)
  }
}

///|
/// runtime に注入する判定関数の形にする。
pub fn JevClient::judge_fn(
  self : JevClient,
) -> async (String, @lib.Comment) -> @lib.Triage {
  (context, comment) => self.judge(context, comment)
}

///|
/// ログに出す形。HTTP エラーはステータスと本文の先頭だけを出す。
pub impl Show for JevError with fn output(self, logger) {
  match self {
    HttpStatus(code, body) => {
      let head = if body.char_length() > 200 {
        body
        .view(end_offset=body.offset_of_nth_char(200).unwrap_or(body.length()))
        .to_owned()
      } else {
        body
      }
      logger.write_string("Jev が HTTP \{code} を返しました: \{head}")
    }
    InvalidJson(message) =>
      logger.write_string(
        "Jev の応答が JSON ではありません: \{message}",
      )
    BadResponse(err) => {
      logger.write_string("Jev の応答を解釈できません: ")
      logger.write_object(Repr(err))
    }
  }
}

///|
/// 待てば直る見込みのある失敗か（レート制限と、ゲートウェイ・サーバ側のエラー）。
fn is_transient_status(code : Int) -> Bool {
  code == 429 || (code >= 500 && code <= 599)
}
