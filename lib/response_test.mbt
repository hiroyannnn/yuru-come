///|
let sample_response : String =
  #|{"model": "jev-latest", "answers": {
  #|  "kind": {"type": "choice", "choice": "correction", "probabilities": {"question": 0.2, "correction": 0.7, "chatter": 0.1}, "confidence": 0.6},
  #|  "priority": {"type": "score", "score": 1.7, "probabilities": {"0": 0.05, "1": 0.2, "2": 0.75}, "legend": {"0": "a", "1": "b", "2": "c"}, "confidence": 0.7}},
  #| "usage": {"input_tokens": 300, "output_tokens": 4}}

///|
fn parse_error(text : String) -> @lib.ResponseError? {
  try @lib.parse_response_text(text) catch {
    err => Some(err)
  } noraise {
    _ => None
  }
}

///|
test "kind の分布と confidence、priority の score を取り出す" {
  let triage = @lib.parse_response_text(sample_response)
  assert_eq(triage.kind, Correction)
  assert_eq(triage.kind_confidence, 0.6)
  assert_eq(triage.kind_probability(Correction), 0.7)
  assert_eq(triage.kind_probability(Question), 0.2)
  assert_eq(triage.kind_probability(Abuse), 0.0)
  assert_eq(triage.priority, 1.7)
  assert_eq(triage.priority_confidence, 0.7)
}

///|
test "score が整数で返っても読める" {
  let text = sample_response.replace(old="\"score\": 1.7", new="\"score\": 2")
  assert_eq(@lib.parse_response_text(text).priority, 2.0)
}

///|
test "壊れた JSON は InvalidJson" {
  assert_true(parse_error("{oops") is Some(InvalidJson(_)))
}

///|
test "欠落は MissingField で、どこが無いかを返す" {
  assert_eq(parse_error("{}"), Some(MissingField("answers")))
  assert_eq(
    parse_error("{\"answers\": {}}"),
    Some(MissingField("answers.kind")),
  )
  let no_priority =
    #|{"answers": {"kind": {"type": "choice", "choice": "greeting", "probabilities": {"greeting": 1}, "confidence": 1}}}
  assert_eq(parse_error(no_priority), Some(MissingField("answers.priority")))
  let no_score = sample_response.replace(old="\"score\": 1.7, ", new="")
  assert_eq(parse_error(no_score), Some(MissingField("answers.priority.score")))
}

///|
test "型不一致は TypeMismatch" {
  assert_eq(parse_error("[]"), Some(TypeMismatch("response")))
  assert_eq(parse_error("{\"answers\": 1}"), Some(TypeMismatch("answers")))
  let wrong_type = sample_response.replace(
    old="\"type\": \"choice\"",
    new="\"type\": \"noul\"",
  )
  assert_eq(parse_error(wrong_type), Some(TypeMismatch("answers.kind.type")))
  let text_score = sample_response.replace(
    old="\"score\": 1.7",
    new="\"score\": \"high\"",
  )
  assert_eq(
    parse_error(text_score),
    Some(TypeMismatch("answers.priority.score")),
  )
  let bad_probability = sample_response.replace(
    old="\"correction\": 0.7",
    new="\"correction\": \"0.7\"",
  )
  assert_eq(
    parse_error(bad_probability),
    Some(TypeMismatch("answers.kind.probabilities.correction")),
  )
}

///|
test "criteria に無い種類が返ったら UnknownKind" {
  let text = sample_response.replace(
    old="\"choice\": \"correction\"",
    new="\"choice\": \"banana\"",
  )
  assert_eq(parse_error(text), Some(UnknownKind("banana")))
}
