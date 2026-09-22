///|
/// 1 コメントに対する Jev の仕分け結果。
pub(all) struct Triage {
  kind : Kind
  /// 種類ごとの確率（key → 確率）
  kind_probabilities : Map[String, Double]
  kind_confidence : Double
  /// 配信者が拾うべき度。0（拾わなくてよい）〜 2（今すぐ拾うべき）の実数
  priority : Double
  priority_confidence : Double
} derive(Debug, Eq, ToJson)

///|
/// レスポンス解釈のエラー。
pub(all) suberror ResponseError {
  InvalidJson(String)
  MissingField(String)
  TypeMismatch(String)
  /// criteria に無い種類が返ってきた
  UnknownKind(String)
} derive(Debug, Eq)

///|
/// その種類の確率。分布に無ければ 0。
pub fn Triage::kind_probability(self : Triage, kind : Kind) -> Double {
  self.kind_probabilities.get(kind.key()).unwrap_or(0.0)
}

///|
/// レスポンス本文（文字列）を解釈する。
pub fn parse_response_text(text : String) -> Triage raise ResponseError {
  let json = @json.parse(text) catch {
    err => raise InvalidJson(err.to_string())
  }
  parse_response(json)
}

///|
/// 解析済みレスポンス JSON から仕分け結果を取り出す。
/// 型不一致・欠落はキャストではなくパターンマッチで検出してエラー型にする。
pub fn parse_response(json : Json) -> Triage raise ResponseError {
  guard json is Object(root) else { raise TypeMismatch("response") }
  let answers = object_field(root, "answers", "answers")
  let kind_path = "answers.\{KIND_QUESTION_KEY}"
  let kind_answer = object_field(answers, KIND_QUESTION_KEY, kind_path)
  expect_type(kind_answer, "choice", kind_path)
  let choice = match kind_answer.get("choice") {
    None => raise MissingField("\{kind_path}.choice")
    Some(String(s)) => s
    Some(_) => raise TypeMismatch("\{kind_path}.choice")
  }
  guard Kind::from_key(choice) is Some(kind) && jev_kinds.contains(kind) else {
    raise UnknownKind(choice)
  }
  let kind_probabilities : Map[String, Double] = Map([])
  for
    key, value in object_field(
      kind_answer,
      "probabilities",
      "\{kind_path}.probabilities",
    ) {
    match value {
      Number(n, ..) => kind_probabilities[key] = n
      _ => raise TypeMismatch("\{kind_path}.probabilities.\{key}")
    }
  }
  let priority_path = "answers.\{PRIORITY_QUESTION_KEY}"
  let priority_answer = object_field(
    answers,
    PRIORITY_QUESTION_KEY,
    priority_path,
  )
  expect_type(priority_answer, "score", priority_path)
  {
    kind,
    kind_probabilities,
    kind_confidence: number_field(kind_answer, "confidence", kind_path),
    priority: number_field(priority_answer, "score", priority_path),
    priority_confidence: number_field(
      priority_answer, "confidence", priority_path,
    ),
  }
}

///|
fn object_field(
  parent : Map[String, Json],
  field : String,
  path : String,
) -> Map[String, Json] raise ResponseError {
  match parent.get(field) {
    None => raise MissingField(path)
    Some(Object(value)) => value
    Some(_) => raise TypeMismatch(path)
  }
}

///|
fn number_field(
  parent : Map[String, Json],
  field : String,
  path : String,
) -> Double raise ResponseError {
  match parent.get(field) {
    None => raise MissingField("\{path}.\{field}")
    Some(Number(n, ..)) => n
    Some(_) => raise TypeMismatch("\{path}.\{field}")
  }
}

///|
/// 回答の `type` が期待どおりか確かめる。
fn expect_type(
  answer : Map[String, Json],
  expected : String,
  path : String,
) -> Unit raise ResponseError {
  match answer.get("type") {
    None => raise MissingField("\{path}.type")
    Some(String(t)) if t == expected => ()
    Some(_) => raise TypeMismatch("\{path}.type")
  }
}
