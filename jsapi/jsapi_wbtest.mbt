///|
const NOW : Double = 1790208000000.0

///|
fn privmsg(user : String, text : String) -> String {
  "@display-name=\{user};user-id=\{user};tmi-sent-ts=1790208000000 :\{user}!\{user}@\{user}.tmi.twitch.tv PRIVMSG #somechannel :\{text}"
}

///|
fn jev_response(kind : String, score : Double) -> String {
  (
    {
      "answers": {
        "kind": {
          "type": "choice",
          "choice": kind,
          "probabilities": Json::object(
            Map::from_array([(kind, Json::number(1.0))]),
          ),
          "confidence": 0.9,
        },
        "priority": { "type": "score", "score": score, "confidence": 0.9 },
      },
    } : Json).stringify()
}

///|
fn state_json(now : Double) -> Json raise {
  @json.parse(app_state(now))
}

///|
test "設定 JSON からアプリを作る。壊れた設定はエラーの文言を返す" {
  assert_eq(app_new("{\"context\": \"雑談配信\"}"), "")
  guard state_json(NOW) is Object({ "context": String(context), .. }) else {
    fail("state が読めない")
  }
  assert_eq(context, "雑談配信")
  assert_true(app_new("{oops").length() > 0)
  assert_true(app_new("{\"pickup_floor\": \"high\"}").contains("pickup_floor"))
}

///|
test "匿名ログインの行を CRLF 区切りで返す" {
  assert_eq(
    app_login_lines("justinfan123", "SomeChannel"),
    "CAP REQ :twitch.tv/tags\r\nNICK justinfan123\r\nJOIN #somechannel\r\n",
  )
}

///|
test "IRC の行を渡すと、PING には返答行を返し、発言は取り込む" {
  app_new("{}") |> ignore
  assert_eq(app_irc_line("PING :tmi.twitch.tv", NOW), "PONG :tmi.twitch.tv\r\n")
  assert_eq(app_irc_line(privmsg("alice", "草"), NOW), "")
  assert_eq(app_irc_line(":tmi.twitch.tv 001 justinfan :Welcome", NOW), "")
  guard state_json(NOW) is Object({ "stats": Object(stats), .. }) else {
    fail("stats がない")
  }
  assert_eq(stats.get("received"), Some(Json::number(1.0)))
  assert_eq(stats.get("early"), Some(Json::number(1.0)))
}

///|
test "1 つのメッセージに複数行が入っていても全部処理する" {
  app_new("{}") |> ignore
  let batch = privmsg("a", "草") +
    "\r\n" +
    privmsg("b", "8888") +
    "\r\nPING :x\r\n"
  assert_eq(app_irc_line(batch, NOW), "PONG :x\r\n")
  guard state_json(NOW) is Object({ "stats": Object(stats), .. }) else {
    fail("stats がない")
  }
  assert_eq(stats.get("received"), Some(Json::number(2.0)))
}

///|
test "判定待ちを取り出して Jev の応答を返すと、気になるコメントに出る" {
  app_new("{\"context\": \"Factorio\"}") |> ignore
  app_irc_line(privmsg("alice", "これ何のゲームですか？"), NOW)
  |> ignore
  let pending = @json.parse(app_take_next())
  guard pending
    is Object(
      {
        "id": Number(id, ..),
        "comment": String(comment),
        "context": String(context),
        ..
      }
    ) else {
    fail("判定待ちが読めない")
  }
  assert_eq(comment, "これ何のゲームですか？")
  assert_eq(context, "Factorio")
  assert_eq(app_take_next(), "")
  app_complete(id.to_int(), jev_response("question", 1.5), NOW + 400)
  guard state_json(NOW + 400) is Object({ "pickups": Array(pickups), .. }) else {
    fail("pickups がない")
  }
  assert_eq(pickups.length(), 1)
}

///|
test "判定に失敗した（空・壊れた応答）ら未判定として数える" {
  app_new("{}") |> ignore
  app_irc_line(privmsg("a", "これ何のゲームですか？"), NOW) |> ignore
  app_irc_line(
    privmsg("b", "今日は仕事が終わってから来ました"),
    NOW,
  )
  |> ignore
  let first = @json.parse(app_take_next())
  let second = @json.parse(app_take_next())
  guard first is Object({ "id": Number(a, ..), .. }) &&
    second is Object({ "id": Number(b, ..), .. }) else {
    fail("判定待ちが読めない")
  }
  app_complete(a.to_int(), "", NOW)
  app_complete(b.to_int(), "{oops", NOW)
  // 知らない ID は無視する
  app_complete(999, jev_response("question", 1.5), NOW)
  guard state_json(NOW) is Object({ "stats": Object(stats), .. }) else {
    fail("stats がない")
  }
  assert_eq(stats.get("failed"), Some(Json::number(2.0)))
}

///|
test "既読（拾った・スルー）の記録を JSONL で取り出す" {
  app_new("{}") |> ignore
  app_irc_line(privmsg("alice", "これ何のゲームですか？"), NOW)
  |> ignore
  guard @json.parse(app_take_next()) is Object({ "id": Number(id, ..), .. }) else {
    fail("判定待ちが読めない")
  }
  app_complete(id.to_int(), jev_response("question", 1.5), NOW)
  guard state_json(NOW)
    is Object(
      { "pickups": Array([Object({ "id": Number(pickup, ..), .. })]), .. }
    ) else {
    fail("pickups がない")
  }
  assert_true(app_dismiss(pickup.to_int(), "skipped", NOW + 10))
  assert_false(app_dismiss(pickup.to_int(), "picked", NOW + 10))
  let labels = app_take_labels()
  assert_true(labels.contains("\"outcome\":\"skipped\""))
  assert_true(labels.has_suffix("\n"))
  assert_eq(app_take_labels(), "")
}

///|
test "要約の入力は新しいコメントがあるときだけ返し、書いた一文は状態に載る" {
  app_new("{}") |> ignore
  assert_eq(app_summary_prompt(NOW), "")
  app_irc_line(privmsg("alice", "これ何のゲームですか？"), NOW)
  |> ignore
  guard @json.parse(app_take_next()) is Object({ "id": Number(id, ..), .. }) else {
    fail("判定待ちが読めない")
  }
  app_complete(id.to_int(), jev_response("question", 1.5), NOW)
  guard @json.parse(app_summary_prompt(NOW))
    is Object({ "system": String(_), "user": String(user), .. }) else {
    fail("要約の入力がない")
  }
  assert_true(user.contains("これ何のゲームですか？"))
  // 同じ状態ではもう返さない
  assert_eq(app_summary_prompt(NOW + 1), "")
  app_set_summary("  「質問が来ています。」", NOW + 2)
  guard state_json(NOW + 2)
    is Object(
      {
        "summary": Object(
          { "text": String(text), "source": String(source), .. }
        ),
        ..
      }
    ) else {
    fail("summary がない")
  }
  assert_eq(text, "質問が来ています。")
  assert_eq(source, "llm")
}

///|
test "商品を設定すると、コメントで話題になったときに状態に載る" {
  app_new(
    "{\"promos\": [{\"label\": \"マイク\", \"url\": \"https://example.com/mic\", \"keywords\": [\"マイク\"]}]}",
  )
  |> ignore
  app_irc_line(privmsg("a", "マイクなに使ってる？"), NOW) |> ignore
  guard state_json(NOW) is Object({ "promos": Array([_]), .. }) else {
    fail("promos がない")
  }
}

///|
test "中継: コメントと文脈から Jev のリクエスト本文を組む。不正な入力は空文字" {
  guard @json.parse(
      judge_body("{\"comment\": \"a\", \"context\": \"c\"}", "typesafe-ai/jev"),
    )
    is Object({ "model": String(model), "state": Object(state), .. }) else {
    fail("本文が読めない")
  }
  assert_eq(model, "typesafe-ai/jev")
  assert_eq(state.get("comment"), Some(Json::string("a")))
  assert_eq(judge_body("{}", "m"), "")
  assert_eq(judge_body("{oops", "m"), "")
}

///|
test "中継の関門: IP ごとの流量制限と 1 日の予算。保存して戻せる" {
  gate_new(2, 1, 60000.0, "")
  assert_eq(gate_check("1.1.1.1", NOW), "ok")
  assert_eq(gate_check("1.1.1.1", NOW + 1), "rate")
  assert_eq(gate_check("2.2.2.2", NOW + 2), "ok")
  assert_eq(gate_check("3.3.3.3", NOW + 3), "budget")
  let saved = gate_dump()
  gate_new(2, 1, 60000.0, saved)
  assert_eq(gate_check("4.4.4.4", NOW + 4), "budget")
}
