///|
fn speak(who : String, text : String) -> @lib.Comment {
  @lib.Comment::new(@lib.participant_id("t", who), text, author=who)
}

///|
fn triage_of(kind : @lib.Kind, priority : Double) -> @lib.Triage {
  {
    kind,
    kind_probabilities: Map([]),
    kind_confidence: 0.9,
    priority,
    priority_confidence: 0.9,
  }
}

///|
/// 反応の波と、判定済みのコメントがいくつかある状態。
fn busy_engine() -> @lib.Engine {
  let engine = @lib.Engine::new(
    config=@lib.EngineConfig::new(context="Factorio 配信"),
  )
  for i in 0..<12 {
    engine.ingest(speak("u\{i}", "草"), i.to_int64() * 100)
  }
  for i in 0..<3 {
    engine.ingest(speak("v\{i}", "8888"), 2000 + i.to_int64())
  }
  engine.ingest(
    speak("pipe", "それ原油じゃなくて重油では？"),
    3000,
  )
  engine.ingest(speak("newbie", "初見です"), 3100)
  engine.ingest(speak("troll", "下手くそ"), 3200)
  let kinds : Array[(@lib.Kind, Double)] = [
    (Correction, 1.8),
    (FirstTime, 1.3),
    (Abuse, 0.0),
  ]
  let mut i = 0
  while engine.take_next() is Some(pending) {
    // 新しい順に取り出されるので、逆から当てる
    let (kind, priority) = kinds[kinds.length() - 1 - i]
    engine.complete(pending, Some(triage_of(kind, priority)), 3500)
    i += 1
  }
  engine
}

///|
test "テンプレートの一文: 上位の反応、種類の件数、流速と人数を並べる" {
  let text = @lib.template_summary(busy_engine().state(3500))
  assert_eq(
    text, "「草」×12、「8888」×3 が続いています。指摘 1、初見 1、荒らし 1。30 秒で 18 件・18 人。",
  )
}

///|
test "テンプレートの一文: 束は上位 3 つまで" {
  let engine = @lib.Engine::new()
  for label in ["a", "b", "c", "d"] {
    for i in 0..<2 {
      engine.ingest(speak("u\{i}", label), 0)
    }
  }
  let text = @lib.template_summary(engine.state(0))
  assert_true(
    text.contains(
      "「a」×2、「b」×2、「c」×2 が続いています。",
    ),
  )
  assert_false(text.contains("「d」"))
}

///|
test "テンプレートの一文: コメントが無ければ静かだと言う" {
  assert_eq(
    @lib.template_summary(@lib.Engine::new().state(0)),
    "この 30 秒はコメントがありません。",
  )
}

///|
test "テンプレートの一文: 束が無ければ反応の部分を省く" {
  let engine = @lib.Engine::new()
  engine.ingest(speak("a", "こんばんは"), 0)
  while engine.take_next() is Some(pending) {
    engine.complete(pending, Some(triage_of(Greeting, 0.5)), 10)
  }
  assert_eq(
    @lib.template_summary(engine.state(10)),
    "挨拶 1。30 秒で 1 件・1 人。",
  )
}

///|
test "LLM への入力: 文脈、束、種類の分布、直近の中身のあるコメントを種類つきで並べる" {
  let prompt = @lib.summary_prompt(busy_engine().state(3500))
  assert_true(prompt.system.contains("一文"))
  assert_true(prompt.system.contains("60"))
  assert_true(prompt.user.contains("配信の文脈: Factorio 配信"))
  assert_true(prompt.user.contains("「草」×12"))
  assert_true(prompt.user.contains("指摘 1"))
  assert_true(
    prompt.user.contains(
      "[指摘] pipe: それ原油じゃなくて重油では？",
    ),
  )
  assert_true(prompt.user.contains("[初見] newbie: 初見です"))
  // 反応と荒らしは並べない
  assert_false(prompt.user.contains("[反応]"))
  assert_false(prompt.user.contains("下手くそ"))
}

///|
test "LLM への入力: 直近のコメントは新しい順に上限まで" {
  let engine = @lib.Engine::new()
  for i in 0..<30 {
    engine.ingest(
      speak("u\{i}", "コメント\{i}について話しています"),
      i.to_int64(),
    )
  }
  while engine.take_next() is Some(pending) {
    engine.complete(pending, Some(triage_of(Chatter, 0.3)), 100)
  }
  let prompt = @lib.summary_prompt(engine.state(100), recent_limit=5)
  assert_true(prompt.user.contains("コメント29について"))
  assert_true(prompt.user.contains("コメント25について"))
  assert_false(prompt.user.contains("コメント24について"))
}

///|
test "呼ぶ価値があるのは、前回から新しいコメントが来ていて、窓が空でないとき" {
  let engine = busy_engine()
  let state = engine.state(3500)
  assert_true(@lib.summary_needed(state, last_entry_id=0))
  let newest = state.flow[0].id
  assert_false(@lib.summary_needed(state, last_entry_id=newest))
  assert_false(
    @lib.summary_needed(@lib.Engine::new().state(0), last_entry_id=0),
  )
}

///|
test "返ってきた文の整形: 前後の空白・引用符・前置きを除き、最初の一文だけにする" {
  assert_eq(
    @lib.clean_summary("  「草が続いています。」\n"),
    "草が続いています。",
  )
  assert_eq(
    @lib.clean_summary("要約: 質問が溜まっています。\n次の行"),
    "質問が溜まっています。",
  )
  assert_eq(@lib.clean_summary("\"Quiet chat.\""), "Quiet chat.")
  assert_eq(@lib.clean_summary(""), "")
}

///|
test "返ってきた文の整形: 長すぎる文は切って … を付ける" {
  let long = "あ".repeat(100)
  let cleaned = @lib.clean_summary(long)
  assert_eq(cleaned.char_length(), 81)
  assert_true(cleaned.has_suffix("…"))
}

///|
test "状態には要約が載り、LLM の要約が無ければテンプレート" {
  let engine = busy_engine()
  let state = engine.state(3500)
  assert_eq(state.summary.source, "template")
  assert_eq(state.summary.text, @lib.template_summary(state))
  engine.set_summary("指摘と初見が来ています。", 3600)
  let with_llm = engine.state(3600)
  assert_eq(with_llm.summary.source, "llm")
  assert_eq(with_llm.summary.text, "指摘と初見が来ています。")
  assert_eq(with_llm.summary.at, 3600)
}

///|
test "LLM の要約は古くなったらテンプレートに戻る（既定 2 分）" {
  let engine = busy_engine()
  engine.set_summary("指摘と初見が来ています。", 3600)
  assert_eq(engine.state(3600 + 119_999).summary.source, "llm")
  assert_eq(engine.state(3600 + 120_000).summary.source, "template")
}
