///|
/// Jev に投げるモデル名の既定。Vercel AI Gateway 経由なら `typesafe-ai/jev` を渡す。
pub const JEV_MODEL : String = "jev-latest"

///|
/// リクエスト内の質問キー。レスポンスの `answers` もこのキーで引く。
pub const KIND_QUESTION_KEY : String = "kind"

///|
pub const PRIORITY_QUESTION_KEY : String = "priority"

///|
pub const KIND_INSTRUCTIONS : String = "これはライブ配信のチャット欄に視聴者が書いたコメントです。このコメントはどの種類か？"

///|
pub const PRIORITY_INSTRUCTIONS : String = "配信者がこのコメントを読み上げたり返事をしたりして拾うべき度合いは？配信者への質問、ミスの指摘、初見の挨拶、配信トラブルの報告は拾うべき。視聴者同士の雑談、ただの相づち、荒らしは拾わなくてよい。"

///|
/// priority の 3 段階（score の 0 / 1 / 2）。
pub let priority_levels : Array[String] = [
  "拾わなくてよい", "余裕があれば拾う", "今すぐ拾うべき",
]

///|
/// TypeSafe Jev 互換 API（`POST /v1/systemone`）向けの仕分けリクエストを組み立てる。
///
/// - `state`: 配信の文脈（任意）とコメント
/// - `questions.kind`: 9 種類を criteria にした choice
/// - `questions.priority`: 「配信者が拾うべき度」の score
///
/// 本家 Jev は質問を増やしても遅延がほぼ増えないので、2 質問を 1 リクエストで送る。
pub fn build_request(
  comment : String,
  context? : String = "",
  model? : String = JEV_MODEL,
) -> Json {
  let state : Map[String, Json] = Map([])
  let context = context.trim(chars=" \t\r\n　").to_owned()
  if !context.is_empty() {
    state["context"] = Json::string(context)
  }
  state["comment"] = Json::string(comment)
  let criteria : Map[String, Json] = Map([])
  for kind in jev_kinds {
    criteria[kind.key()] = Json::string(kind.description())
  }
  {
    "state": Json::object(state),
    "model": model,
    "questions": {
      "kind": {
        "type": "choice",
        "instructions": KIND_INSTRUCTIONS,
        "criteria": Json::object(criteria),
      },
      "priority": {
        "type": "score",
        "instructions": PRIORITY_INSTRUCTIONS,
        "criteria": priority_levels.to_json(),
      },
    },
  }
}
