///|
fn record(
  mood : @lib.Mood,
  at : Int64,
  who : String,
  kind : @lib.Kind,
  reaction? : String,
) -> Unit {
  mood.record(at, @lib.participant_id("test", who), kind, reaction?) |> ignore
}

///|
test "窓の中の種類ごとの件数と合計を出す" {
  let mood = @lib.Mood::new()
  record(mood, 1000, "a", Reaction, reaction="草")
  record(mood, 2000, "b", Reaction, reaction="草")
  record(mood, 3000, "c", Question)
  let snapshot = mood.snapshot(3000, 30_000)
  assert_eq(snapshot.total, 3)
  assert_eq(snapshot.by_kind.get("reaction"), Some(2))
  assert_eq(snapshot.by_kind.get("question"), Some(1))
  assert_eq(snapshot.by_kind.get("abuse"), None)
}

///|
test "30 秒窓と 5 分窓で別々に数えられる" {
  let mood = @lib.Mood::new()
  record(mood, 0, "a", Greeting)
  record(mood, 100_000, "b", Feedback)
  record(mood, 290_000, "c", Question)
  assert_eq(mood.snapshot(300_000, 30_000).total, 1)
  // 窓の端（ちょうど 5 分前）は含む
  assert_eq(mood.snapshot(300_000, 300_000).total, 3)
  assert_eq(mood.snapshot(300_001, 300_000).total, 2)
  assert_eq(mood.snapshot(300_001, 300_000).by_kind.get("greeting"), None)
}

///|
test "流速は 窓の件数 ÷ 窓の秒数" {
  let mood = @lib.Mood::new()
  for i in 0..<60 {
    record(mood, (i * 500).to_int64(), "u\{i}", Reaction, reaction="w")
  }
  assert_eq(mood.snapshot(30_000, 30_000).rate_per_sec, 2.0)
}

///|
test "参加者数は窓の中の重複を除いた人数" {
  let mood = @lib.Mood::new()
  record(mood, 0, "a", Chatter)
  record(mood, 10, "a", Chatter)
  record(mood, 20, "b", Chatter)
  assert_eq(mood.snapshot(100, 30_000).participants, 2)
}

///|
test "上位の反応は件数の多い順で、2 件以上のものだけ" {
  let mood = @lib.Mood::new()
  for i in 0..<5 {
    record(mood, i.to_int64(), "u\{i}", Reaction, reaction="8888")
  }
  for i in 0..<3 {
    record(mood, i.to_int64(), "u\{i}", Reaction, reaction="草")
  }
  record(mood, 10, "x", Reaction, reaction="ナイス")
  record(mood, 11, "y", Question)
  let top = mood.snapshot(100, 30_000).top_reactions
  assert_eq(top, [{ label: "8888", count: 5, }, { label: "草", count: 3, }])
}

///|
test "上位の反応は個数の上限を指定できる" {
  let mood = @lib.Mood::new()
  for label in ["a", "b", "c"] {
    record(mood, 0, "u1", Reaction, reaction=label)
    record(mood, 1, "u2", Reaction, reaction=label)
  }
  assert_eq(mood.snapshot(10, 30_000, top=2).top_reactions.length(), 2)
}

///|
test "保持期間（既定 5 分）を過ぎた記録は捨てる" {
  let mood = @lib.Mood::new()
  record(mood, 0, "a", Chatter)
  record(mood, 400_000, "b", Chatter)
  assert_eq(mood.size(), 1)
}

///|
test "あとから判定が決まったら種類を付け替えられる" {
  let mood = @lib.Mood::new()
  let id = mood.record(0, "test:a", Unjudged)
  mood.reclassify(id, Question)
  let snapshot = mood.snapshot(10, 30_000)
  assert_eq(snapshot.by_kind.get("question"), Some(1))
  assert_eq(snapshot.by_kind.get("unjudged"), None)
  assert_eq(snapshot.total, 1)
}

///|
test "同じ反応キーでも原文がゆれるときは、いちばん短い原文を見出しにする" {
  let mood = @lib.Mood::new()
  mood.record(
    0,
    "test:a",
    Reaction,
    reaction="かわい",
    label="かわいいいい！",
  )
  |> ignore
  mood.record(1, "test:b", Reaction, reaction="かわい", label="かわいい")
  |> ignore
  assert_eq(mood.snapshot(10, 30_000).top_reactions, [
    { label: "かわいい", count: 2, },
  ])
}
