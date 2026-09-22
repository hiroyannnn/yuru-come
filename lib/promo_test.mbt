///|
let promos_json : String =
  #|[
  #| {"label": "配信で使ってるマイク", "url": "https://example.com/mic", "keywords": ["マイク", "mic", "音質"]},
  #| {"label": "今日のゲーム", "url": "https://example.com/game", "keywords": ["どこで買え", "セール"]}
  #|]

///|
test "promos.json を読む" {
  let promos = @lib.parse_promos(@json.parse(promos_json))
  assert_eq(promos.length(), 2)
  assert_eq(promos[0].label, "配信で使ってるマイク")
  assert_eq(promos[0].url, "https://example.com/mic")
  assert_eq(promos[0].keywords, ["マイク", "mic", "音質"])
}

///|
test "label・url・keywords が欠けている・型が違う・keywords が空なら PromoError" {
  let cases : Array[(String, String)] = [
    ("[{\"url\": \"u\", \"keywords\": [\"a\"]}]", "label"),
    ("[{\"label\": \"l\", \"keywords\": [\"a\"]}]", "url"),
    ("[{\"label\": \"l\", \"url\": \"u\"}]", "keywords"),
    ("[{\"label\": \"l\", \"url\": \"u\", \"keywords\": []}]", "keywords"),
    ("[{\"label\": \"l\", \"url\": \"u\", \"keywords\": [1]}]", "keywords"),
    ("{}", "promos"),
  ]
  for pair in cases {
    let (text, field) = pair
    let json = @json.parse(text)
    try @lib.parse_promos(json) catch {
      e => assert_eq(e, @lib.PromoError::Invalid(field))
    } noraise {
      _ => fail("失敗するはず: \{text}")
    }
  }
}

///|
fn board() -> @lib.PromoBoard raise {
  @lib.PromoBoard::new(@lib.parse_promos(@json.parse(promos_json)))
}

///|
test "コメントがキーワードに当たったら、その商品を出す" {
  let board = board()
  let shown = board.notice("そのマイクの機種なんですか？", 1000)
  assert_eq(shown.map(p => p.label), Some("配信で使ってるマイク"))
  let active = board.active(1000)
  assert_eq(active.length(), 1)
  assert_eq(active[0].url, "https://example.com/mic")
  assert_eq(active[0].trigger, "そのマイクの機種なんですか？")
  assert_eq(active[0].shown_at, 1000)
}

///|
test "キーワードは正規化して照合する（全角半角・大文字小文字）" {
  assert_true(board().notice("ＭＩＣ いいね", 0) is Some(_))
  assert_true(board().notice("音質よすぎ", 0) is Some(_))
  assert_eq(board().notice("こんばんは", 0), None)
}

///|
test "表示は一定時間で消え、同じ商品はしばらく出し直さない" {
  let board = @lib.PromoBoard::new(
    @lib.parse_promos(@json.parse(promos_json)),
    config=@lib.PromoConfig::new(show_ms=60_000, cooldown_ms=300_000),
  )
  board.notice("マイク", 0) |> ignore
  assert_eq(board.active(59_999).length(), 1)
  assert_eq(board.active(60_000).length(), 0)
  // 5 分たつまでは同じ商品を出し直さない
  assert_eq(board.notice("マイク", 100_000), None)
  assert_true(board.notice("マイク", 300_000) is Some(_))
}

///|
test "別の商品は同時に出せる" {
  let board = board()
  board.notice("マイク", 0) |> ignore
  board.notice("これどこで買えますか", 10) |> ignore
  assert_eq(board.active(10).map(p => p.label), [
    "配信で使ってるマイク", "今日のゲーム",
  ])
}

///|
test "エンジンはコメントを取り込むときに商品の話題を拾い、状態に載せる" {
  let engine = @lib.Engine::new(
    config=@lib.EngineConfig::new(
      promos=@lib.parse_promos(@json.parse(promos_json)),
    ),
  )
  engine.ingest(@lib.Comment::new("t:a", "マイクなに使ってる？"), 0)
  let state = engine.state(0)
  assert_eq(state.promos.map(p => p.label), ["配信で使ってるマイク"])
  assert_eq(engine.state(61_000).promos, [])
}

///|
test "URL を QR の SVG にできる" {
  guard @lib.qr_svg("https://example.com/mic") is Some(svg) else {
    fail("QR が作れない")
  }
  assert_true(svg.has_prefix("<svg"))
  assert_eq(@lib.qr_svg(""), None)
}
