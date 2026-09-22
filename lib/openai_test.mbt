///|
test "chat/completions のボディ: model、messages、max_completion_tokens、reasoning_effort" {
  let body = @lib.build_chat_request("gpt-5-mini", [
    { role: System, content: "sys", },
    { role: User, content: "hi", },
  ])
  assert_eq(body, {
    "model": "gpt-5-mini",
    "messages": [
      { "role": "system", "content": "sys" },
      { "role": "user", "content": "hi" },
    ],
    "max_completion_tokens": 1024,
    "reasoning_effort": "minimal",
  })
}

///|
test "reasoning_effort は外せる" {
  guard @lib.build_chat_request("m", [], reasoning_effort=None) is Object(body) else {
    fail("object でない")
  }
  assert_false(body.contains("reasoning_effort"))
}

///|
test "2xx の応答から choices[0].message.content を取り出す" {
  let body =
    #|{"choices":[{"message":{"role":"assistant","content":"草が続いています。"}}]}
  assert_eq(@lib.parse_chat_response(200, body), "草が続いています。")
}

///|
fn chat_error(status : Int, body : String) -> @lib.OpenAiError? {
  try @lib.parse_chat_response(status, body) catch {
    err => Some(err)
  } noraise {
    _ => None
  }
}

///|
test "ステータスごとのエラー型と、error.message の取り出し" {
  assert_eq(
    chat_error(401, "{\"error\":{\"message\":\"bad key\"}}"),
    Some(Unauthorized("bad key")),
  )
  assert_eq(chat_error(429, "slow down"), Some(RateLimited("slow down")))
  assert_true(chat_error(503, "{}") is Some(ServerError(code=503, ..)))
  assert_true(chat_error(400, "{}") is Some(BadRequest(code=400, ..)))
  assert_true(chat_error(200, "{oops") is Some(InvalidJson(_)))
  assert_true(chat_error(200, "{\"choices\":[]}") is Some(MissingContent(_)))
}

///|
test "reasoning_effort をモデルが拒否した 400 を見分ける" {
  let err : @lib.OpenAiError = BadRequest(
    code=400,
    message="Unsupported parameter: 'reasoning_effort' is not supported with this model.",
  )
  assert_true(err.is_unsupported_parameter("reasoning_effort"))
  assert_false(err.is_unsupported_parameter("temperature"))
}
