///|
test "state にコメントと配信の文脈を入れる" {
  let json = @lib.build_request(
    "それ原油じゃなくて重油のタンクにつないでない？",
    context="Factorio 配信。いま石油精製を組んでいる",
  )
  guard json is Object({ "state": state, .. }) else { fail("state がない") }
  assert_eq(state, {
    "context": "Factorio 配信。いま石油精製を組んでいる",
    "comment": "それ原油じゃなくて重油のタンクにつないでない？",
  })
}

///|
test "文脈が無い・空のときは state に context を入れない" {
  guard @lib.build_request("こんにちは") is Object({ "state": state, .. }) else {
    fail("state がない")
  }
  assert_eq(state, { "comment": "こんにちは" })
  guard @lib.build_request("こんにちは", context="  ")
    is Object({ "state": blank, .. }) else {
    fail("state がない")
  }
  assert_eq(blank, { "comment": "こんにちは" })
}

///|
test "model の既定は jev-latest で、差し替えられる" {
  guard @lib.build_request("a") is Object({ "model": String(model), .. }) else {
    fail("model がない")
  }
  assert_eq(model, "jev-latest")
  guard @lib.build_request("a", model="typesafe-ai/jev")
    is Object({ "model": String(gateway), .. }) else {
    fail("model がない")
  }
  assert_eq(gateway, "typesafe-ai/jev")
}

///|
test "kind は 9 種類を criteria にした choice 質問" {
  guard @lib.build_request("a")
    is Object({ "questions": Object({ "kind": Object(kind), .. }), .. }) else {
    fail("questions.kind がない")
  }
  assert_eq(kind.get("type"), Some(Json::string("choice")))
  assert_true(kind.get("instructions") is Some(String(_)))
  guard kind.get("criteria") is Some(Object(criteria)) else {
    fail("criteria がない")
  }
  assert_eq(criteria.keys().collect(), [
    "question", "request", "feedback", "correction", "greeting", "first_time", "trouble",
    "abuse", "chatter",
  ])
  for key, description in criteria {
    guard description is String(text) else {
      fail("\{key} が文字列でない")
    }
    assert_true(text.char_length() >= 10, msg=key)
  }
}

///|
test "priority は 3 段階の score 質問で、1 リクエストに 2 質問とも入れる" {
  guard @lib.build_request("a")
    is Object({ "questions": Object(questions), .. }) else {
    fail("questions がない")
  }
  assert_eq(questions.keys().collect(), ["kind", "priority"])
  guard questions.get("priority") is Some(Object(priority)) else {
    fail("questions.priority がない")
  }
  assert_eq(priority.get("type"), Some(Json::string("score")))
  assert_eq(
    priority.get("criteria"),
    Some([
      "拾わなくてよい", "余裕があれば拾う", "今すぐ拾うべき",
    ]),
  )
}

///|
test "Kind は key と相互変換でき、Jev に聞く 9 種類と内部用の 2 種類がある" {
  assert_eq(@lib.jev_kinds.length(), 9)
  for kind in @lib.jev_kinds {
    assert_eq(@lib.Kind::from_key(kind.key()), Some(kind))
  }
  assert_eq(@lib.Kind::from_key("reaction"), Some(Reaction))
  assert_eq(@lib.Kind::from_key("unjudged"), Some(Unjudged))
  assert_eq(@lib.Kind::from_key("banana"), None)
  assert_eq(@lib.Kind::FirstTime.to_json(), Json::string("first_time"))
}
