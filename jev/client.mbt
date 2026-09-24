///|
/// yuru-come の仕分け。送信と一時的な失敗の再試行は yuru-kit の JevClient に任せ、
/// ここでは kind と priority の 2 質問の組み立てと、応答の解釈だけを行う。
pub suberror JevError {
  /// 応答は JSON だが、期待した形ではない
  BadResponse(@lib.ResponseError)
} derive(Debug)

///|
pub struct JevClient {
  transport : @kit_jev.JevClient
}

///|
/// 環境変数 JEV_URL / JEV_API_KEY / JEV_MODEL から作る。
pub fn JevClient::from_env() -> JevClient {
  { transport: @kit_jev.JevClient::from_env(), }
}

///|
pub fn JevClient::new(transport : @kit_jev.JevClient) -> JevClient {
  { transport, }
}

///|
/// 1 コメントを仕分ける。kind と priority の 2 質問を 1 リクエストで送る。
pub async fn JevClient::judge(
  self : JevClient,
  context : String,
  comment : @lib.Comment,
) -> @lib.Triage {
  let request = @lib.build_request(
    comment.text,
    context~,
    model=self.transport.model,
  )
  let response = self.transport.systemone(request)
  @lib.parse_response(response) catch {
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
pub impl Show for JevError with fn output(self, logger) {
  match self {
    BadResponse(err) => {
      logger.write_string("Jev の応答を解釈できません: ")
      logger.write_object(Repr(err))
    }
  }
}
