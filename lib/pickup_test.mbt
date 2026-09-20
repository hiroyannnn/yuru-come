///|
fn say(text : String) -> @lib.Comment {
  @lib.Comment::new("test:viewer", text)
}

///|
test "question / request / correction / first_time / trouble は priority が低くても拾う" {
  let list = @lib.PickupList::new()
  let kinds : Array[@lib.Kind] = [
    Question,
    Request,
    Correction,
    FirstTime,
    Trouble,
  ]
  for kind in kinds {
    assert_true(list.offer(say("a"), kind, 0.2, 0) is Some(_), msg=kind.key())
  }
  assert_eq(list.view(0).length(), 5)
}

///|
test "それ以外の種類は priority が 1.5 以上のときだけ拾う" {
  let list = @lib.PickupList::new()
  assert_true(list.offer(say("神回だった"), Feedback, 1.6, 0) is Some(_))
  assert_true(list.offer(say("こんばんは"), Greeting, 1.5, 0) is Some(_))
  assert_eq(list.offer(say("おもしろい"), Feedback, 1.4, 0), None)
  assert_eq(list.offer(say("明日仕事だ"), Chatter, 0.1, 0), None)
  assert_eq(list.view(0).length(), 2)
}

///|
test "abuse・reaction・未判定は priority が高くても拾わない" {
  let list = @lib.PickupList::new()
  assert_eq(list.offer(say("消えろ"), Abuse, 2.0, 0), None)
  assert_eq(list.offer(say("草"), Reaction, 2.0, 0), None)
  assert_eq(list.offer(say("？"), Unjudged, 2.0, 0), None)
  assert_eq(list.view(0), [])
}

///|
test "閾値は設定で変えられる" {
  let list = @lib.PickupList::new(
    config=@lib.PickupConfig::new(priority_threshold=1.0),
  )
  assert_true(list.offer(say("おもしろい"), Feedback, 1.2, 0) is Some(_))
}

///|
test "並びは trouble が最上位、次に priority の高い順、同じなら新しい順" {
  let list = @lib.PickupList::new()
  list.offer(say("質問 低"), Question, 0.8, 100) |> ignore
  list.offer(say("指摘 高"), Correction, 1.9, 200) |> ignore
  list.offer(say("音が出てない"), Trouble, 1.0, 300) |> ignore
  list.offer(say("質問 低 新しい"), Question, 0.8, 400) |> ignore
  let view = list.view(500)
  assert_eq(view.map(item => item.comment.text), [
    "音が出てない", "指摘 高", "質問 低 新しい", "質問 低",
  ])
  assert_eq(view.map(item => item.pinned), [true, false, false, false])
}

///|
test "既読にした項目は消える" {
  let list = @lib.PickupList::new()
  guard list.offer(say("これ何のゲーム？"), Question, 1.2, 0)
    is Some(id) else {
    fail("拾われなかった")
  }
  list.offer(say("初見です"), FirstTime, 1.8, 0) |> ignore
  assert_true(list.dismiss(id))
  assert_eq(list.view(0).map(item => item.comment.text), ["初見です"])
  assert_false(list.dismiss(id))
  assert_false(list.dismiss(999))
}

///|
test "5 分たつと薄くなり、10 分たつと消える" {
  let list = @lib.PickupList::new()
  list.offer(say("これ何のゲーム？"), Question, 1.2, 0) |> ignore
  assert_eq(list.view(299_999L).map(item => item.faded), [false])
  assert_eq(list.view(300_000L).map(item => item.faded), [true])
  assert_eq(list.view(599_999L).length(), 1)
  assert_eq(list.view(600_000L), [])
}

///|
test "同じコメントが重ねて来たら件数を増やせる" {
  let list = @lib.PickupList::new()
  guard list.offer(say("これ何のゲーム？"), Question, 1.2, 0)
    is Some(id) else {
    fail("拾われなかった")
  }
  assert_eq(list.view(0)[0].count, 1)
  list.bump(id) |> ignore
  list.bump(id) |> ignore
  assert_eq(list.view(0)[0].count, 3)
}

///|
test "項目の ID は重複しない" {
  let list = @lib.PickupList::new()
  let a = list.offer(say("a"), Question, 1.0, 0)
  let b = list.offer(say("b"), Question, 1.0, 0)
  assert_true(a is Some(_) && b is Some(_) && a != b)
}

///|
test "画面を見ていなくても、新しく拾うたびに期限切れを捨てる" {
  let list = @lib.PickupList::new()
  list.offer(say("古い質問？"), Question, 1.0, 0) |> ignore
  list.offer(say("新しい質問？"), Question, 1.0, 700_000) |> ignore
  assert_eq(list.size(), 1)
}

///|
test "件数を増やせたかどうかが分かる" {
  let list = @lib.PickupList::new()
  guard list.offer(say("質問？"), Question, 1.0, 0) is Some(id) else {
    fail("拾われなかった")
  }
  assert_true(list.bump(id))
  list.dismiss(id) |> ignore
  assert_false(list.bump(id))
}
