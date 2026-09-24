///|
fn judge_error(json : Json) -> @lib.JudgeRequestError? {
  try @lib.parse_judge_request(json) catch {
    err => Some(err)
  } noraise {
    _ => None
  }
}

///|
test "中継はコメントと文脈だけを受け取る" {
  let request = @lib.parse_judge_request({
    "comment": "これ何のゲームですか？",
    "context": "雑談配信",
  })
  assert_eq(request.comment, "これ何のゲームですか？")
  assert_eq(request.context, "雑談配信")
  // 文脈は省略できる
  assert_eq(@lib.parse_judge_request({ "comment": "a" }).context, "")
}

///|
test "コメントが無い・空・長すぎる、文脈が長すぎるものは断る" {
  assert_eq(judge_error({ "context": "x" }), Some(MissingComment))
  assert_eq(judge_error({ "comment": "  " }), Some(MissingComment))
  assert_eq(judge_error({ "comment": 1 }), Some(MissingComment))
  assert_eq(
    judge_error({ "comment": "あ".repeat(501) }),
    Some(TooLong("comment")),
  )
  assert_eq(
    judge_error({ "comment": "a", "context": "あ".repeat(201) }),
    Some(TooLong("context")),
  )
  assert_eq(judge_error(Json::null()), Some(MissingComment))
}

///|
test "上限ちょうどは通す" {
  let request = @lib.parse_judge_request({
    "comment": "あ".repeat(500),
    "context": "あ".repeat(200),
  })
  assert_eq(request.comment.char_length(), 500)
}

///|
test "余計なフィールド（任意の質問など）は無視して、Jev への質問は中継側で組む" {
  let request = @lib.parse_judge_request({
    "comment": "a",
    "questions": { "evil": { "type": "choice" } },
  })
  guard @lib.build_request(request.comment, context=request.context)
    is Object({ "questions": Object(questions), .. }) else {
    fail("questions がない")
  }
  assert_eq(questions.keys().collect(), ["kind", "priority"])
}
