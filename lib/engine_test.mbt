///|
fn viewer(who : String, text : String) -> @lib.Comment {
  @lib.Comment::new(@lib.participant_id("test", who), text, author=who)
}

///|
fn triage(kind : @lib.Kind, priority : Double) -> @lib.Triage {
  {
    kind,
    kind_probabilities: Map([]),
    kind_confidence: 0.9,
    priority,
    priority_confidence: 0.9,
  }
}

///|
/// キーワードで決める偽の判定関数。HTTP なしでエンジンを試すためのもの。
fn fake_judge(comment : @lib.Comment) -> @lib.Triage? {
  let text = comment.text
  if text.contains("判定失敗") {
    None
  } else if text.contains("音が") {
    Some(triage(Trouble, 2.0))
  } else if text.contains("？") {
    Some(triage(Question, 1.2))
  } else if text.contains("消えろ") {
    Some(triage(Abuse, 0.0))
  } else {
    Some(triage(Chatter, 0.2))
  }
}

///|
/// キューが空になるまで偽の判定を回し、Jev を呼んだ回数を返す。
fn judge_all(engine : @lib.Engine, now : Int64) -> Int {
  let mut calls = 0
  while engine.take_next() is Some(pending) {
    calls += 1
    engine.complete(pending, fake_judge(pending.comment), now)
  }
  calls
}

///|
fn flow_kinds(engine : @lib.Engine, now : Int64) -> Array[(String, @lib.Kind)] {
  engine.state(now).flow.map(entry => (entry.comment.text, entry.kind))
}

///|
test "反応は Jev のキューに入らず、その場で reaction に決まる" {
  let engine = @lib.Engine::new()
  engine.ingest(viewer("a", "草"), 0)
  engine.ingest(viewer("b", "wwww"), 10)
  let state = engine.state(10)
  assert_eq(state.stats.queue_length, 0)
  assert_eq(state.stats.received, 2)
  assert_eq(state.stats.early, 2)
  assert_eq(flow_kinds(engine, 10), [("wwww", Reaction), ("草", Reaction)])
  assert_eq(engine.take_next(), None)
}

///|
test "中身のあるコメントは判定待ちになり、判定が返ると拾い上げと空気に反映される" {
  let engine = @lib.Engine::new()
  engine.ingest(viewer("a", "これ何のゲームですか？"), 0)
  let waiting = engine.state(0)
  assert_eq(waiting.stats.queue_length, 1)
  assert_eq(waiting.flow[0].status, Pending)
  assert_eq(waiting.pickups, [])
  assert_eq(judge_all(engine, 500), 1)
  let state = engine.state(500)
  assert_eq(state.stats.queue_length, 0)
  assert_eq(state.stats.judged, 1)
  assert_eq(state.flow[0].status, Judged)
  assert_eq(state.flow[0].kind, Question)
  assert_eq(state.flow[0].priority, Some(1.2))
  assert_eq(state.pickups.map(item => item.comment.text), [
    "これ何のゲームですか？",
  ])
  assert_eq(state.mood_short.by_kind.get("question"), Some(1))
  assert_eq(state.mood_short.by_kind.get("unjudged"), None)
}

///|
test "判定済みと同じコメントは Jev を呼ばずに同じ種類になり、拾い上げの件数が増える" {
  let engine = @lib.Engine::new()
  engine.ingest(viewer("a", "これ何のゲームですか？"), 0)
  assert_eq(judge_all(engine, 100), 1)
  engine.ingest(viewer("b", "これ何のゲームですか？？"), 200)
  engine.ingest(viewer("c", "これ何のゲームですか"), 300)
  assert_eq(judge_all(engine, 400), 0)
  let state = engine.state(400)
  assert_eq(state.flow.map(entry => entry.status), [
    Inherited,
    Inherited,
    Judged,
  ])
  assert_eq(state.flow.map(entry => entry.kind), [Question, Question, Question])
  assert_eq(state.pickups.length(), 1)
  assert_eq(state.pickups[0].count, 3)
  assert_eq(state.stats.inherited, 2)
}

///|
test "判定待ちのコメントと同じものが来たら、先頭の判定を待って相乗りする" {
  let engine = @lib.Engine::new()
  engine.ingest(viewer("a", "音が出てないよ"), 0)
  engine.ingest(viewer("b", "音が出てないよ！"), 10)
  assert_eq(engine.state(10).stats.queue_length, 1)
  assert_eq(judge_all(engine, 500), 1)
  let state = engine.state(500)
  assert_eq(state.flow.map(entry => entry.kind), [Trouble, Trouble])
  assert_eq(state.pickups.length(), 1)
  assert_eq(state.pickups[0].count, 2)
}

///|
test "拾うべき種類の束に類似度だけで入ったコメントは、相乗りさせず個別に判定する" {
  let engine = @lib.Engine::new()
  engine.ingest(viewer("a", "これ何の曲ですか？"), 0)
  assert_eq(judge_all(engine, 100), 1)
  engine.ingest(viewer("b", "これ何の本ですか？"), 200)
  assert_eq(judge_all(engine, 300), 1)
  assert_eq(engine.state(300).pickups.length(), 2)
}

///|
test "拾わなくてよい種類の束に類似度で入ったコメントは相乗りする" {
  let engine = @lib.Engine::new()
  engine.ingest(viewer("a", "これは無料ですわ"), 0)
  assert_eq(judge_all(engine, 100), 1)
  engine.ingest(viewer("b", "これは有料ですわ"), 200)
  assert_eq(judge_all(engine, 300), 0)
  assert_eq(engine.state(300).flow[0].kind, Chatter)
}

///|
test "キューが上限を超えたら、古い半分のうちいちばん短いコメントを未判定のまま流す" {
  let engine = @lib.Engine::new(config=@lib.EngineConfig::new(queue_limit=4))
  engine.ingest(
    viewer("a", "いちばん古くて長めのコメントです"),
    0,
  )
  engine.ingest(viewer("b", "古くて短い"), 10)
  engine.ingest(viewer("c", "三番目のそこそこ長いコメント"), 20)
  engine.ingest(viewer("d", "新しい短め"), 30)
  assert_eq(engine.state(30).stats.dropped, 0)
  engine.ingest(viewer("e", "あふれさせる五番目のコメント"), 40)
  let state = engine.state(40)
  assert_eq(state.stats.queue_length, 4)
  assert_eq(state.stats.dropped, 1)
  let dropped = state.flow.filter(entry => entry.status == Dropped)
  assert_eq(dropped.map(entry => entry.comment.text), ["古くて短い"])
  assert_eq(dropped[0].kind, Unjudged)
  // 取り込みは止まらず、残りは順に判定される
  assert_eq(judge_all(engine, 100), 4)
  assert_eq(engine.state(100).stats.judged, 4)
}

///|
test "落としたコメントと同じものがまた来たら、あらためて判定に回す" {
  let engine = @lib.Engine::new(config=@lib.EngineConfig::new(queue_limit=1))
  engine.ingest(viewer("a", "短い質問？"), 0)
  engine.ingest(viewer("b", "こちらはもっと長い質問です？"), 10)
  assert_eq(engine.state(10).stats.dropped, 1)
  assert_eq(judge_all(engine, 20), 1)
  engine.ingest(viewer("c", "短い質問？"), 30)
  assert_eq(judge_all(engine, 40), 1)
  assert_eq(engine.state(40).flow[0].kind, Question)
}

///|
test "落とした先頭に相乗りしていたコメントも、未判定のまま流れに出る" {
  let engine = @lib.Engine::new(config=@lib.EngineConfig::new(queue_limit=1))
  engine.ingest(viewer("a", "短い質問？"), 0)
  engine.ingest(viewer("b", "短い質問？"), 5)
  engine.ingest(viewer("c", "こちらはもっと長い質問です？"), 10)
  let state = engine.state(10)
  assert_eq(state.stats.dropped, 2)
  assert_eq(state.stats.inherited, 0)
  assert_eq(state.flow.map(entry => entry.status), [Pending, Dropped, Dropped])
}

///|
test "判定に失敗したコメントは未判定として流れにだけ出る" {
  let engine = @lib.Engine::new()
  engine.ingest(viewer("a", "これは判定失敗するコメント"), 0)
  assert_eq(judge_all(engine, 100), 1)
  let state = engine.state(100)
  assert_eq(state.flow[0].status, Failed)
  assert_eq(state.flow[0].kind, Unjudged)
  assert_eq(state.stats.failed, 1)
  assert_eq(state.pickups, [])
}

///|
test "abuse は拾い上げに入らず、流れには abuse として出る" {
  let engine = @lib.Engine::new()
  engine.ingest(viewer("a", "下手くそ消えろ"), 0)
  judge_all(engine, 100) |> ignore
  let state = engine.state(100)
  assert_eq(state.pickups, [])
  assert_eq(state.flow[0].kind, Abuse)
}

///|
test "既読にすると拾い上げから消える" {
  let engine = @lib.Engine::new()
  engine.ingest(viewer("a", "これ何のゲームですか？"), 0)
  judge_all(engine, 100) |> ignore
  let id = engine.state(100).pickups[0].id
  assert_true(engine.dismiss(id))
  assert_eq(engine.state(100).pickups, [])
}

///|
test "束ねられた反応は件数つきで空気に出る" {
  let engine = @lib.Engine::new()
  for i in 0..<48 {
    engine.ingest(
      viewer("u\{i % 20}", "草" + "w".repeat(i % 5)),
      i.to_int64() * 100,
    )
  }
  engine.ingest(viewer("x", "8888"), 5000)
  let state = engine.state(5000)
  assert_eq(state.bundles.length(), 1)
  assert_eq(state.bundles[0].representative, "草")
  assert_eq(state.bundles[0].count, 48)
  assert_eq(state.bundles[0].participants, 20)
  assert_eq(state.mood_short.top_reactions, [{ label: "草", count: 48, }])
  assert_eq(state.mood_long.total, 49)
}

///|
test "流れは新しい順で、上限を超えた古いものは捨てる" {
  let engine = @lib.Engine::new(config=@lib.EngineConfig::new(flow_limit=3))
  for i in 0..<5 {
    engine.ingest(viewer("a", "草"), i.to_int64())
  }
  assert_eq(engine.state(10).flow.map(entry => entry.id), [5, 4, 3])
}

///|
struct Recorder {
  seen : Array[(String, @lib.Kind)]
}

///|
impl @lib.Sink for Recorder with fn on_entry(self, entry) {
  self.seen.push((entry.comment.text, entry.kind))
}

///|
test "Sink には種類が決まった時点で通知する（判定待ちの間は通知しない）" {
  let engine = @lib.Engine::new()
  let recorder : Recorder = { seen: [], }
  engine.add_sink(recorder)
  engine.ingest(viewer("a", "草"), 0)
  engine.ingest(viewer("b", "これ何のゲームですか？"), 10)
  assert_eq(recorder.seen, [("草", Reaction)])
  judge_all(engine, 100) |> ignore
  assert_eq(recorder.seen, [
    ("草", Reaction),
    ("これ何のゲームですか？", Question),
  ])
}

///|
test "設定で足した辞書の語は早期判定に効く" {
  let engine = @lib.Engine::new(
    config=@lib.EngineConfig::new(reaction_words=["てぇてぇ"]),
  )
  engine.ingest(viewer("a", "てぇてぇ"), 0)
  assert_eq(engine.state(0).stats.early, 1)
}

///|
test "状態は JSON にできる" {
  let engine = @lib.Engine::new(
    config=@lib.EngineConfig::new(context="雑談配信"),
  )
  engine.ingest(viewer("a", "草"), 0)
  guard engine.state(0).to_json() is Object(root) else {
    fail("object でない")
  }
  for
    key in [
      "now", "context", "pickups", "bundles", "mood_short", "mood_long", "flow",
      "stats",
    ] {
    assert_true(root.contains(key), msg=key)
  }
}
