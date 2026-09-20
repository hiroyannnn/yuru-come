///|
fn entry(
  kind : @lib.Kind,
  status : @lib.JudgeStatus,
  pickup_id : Int?,
  priority? : Double,
) -> @lib.FlowEntry {
  {
    id: 1,
    comment: @lib.Comment::new(
      "twitch:1",
      "これ何のゲーム？",
      author="Alice",
    ),
    kind,
    priority,
    status,
    pickup_id,
  }
}

///|
test "拾い上げに入ったコメントを 1 行にする（種類・priority・プラットフォーム・投稿者・本文）" {
  assert_eq(
    @lib.render_pickup_line(entry(Question, Judged, Some(3), priority=1.25)),
    Some("[質問 1.3] twitch/Alice: これ何のゲーム？"),
  )
}

///|
test "trouble は目立つ印を付ける" {
  assert_eq(
    @lib.render_pickup_line(entry(Trouble, Judged, Some(3), priority=2.0)),
    Some("!! [トラブル 2.0] twitch/Alice: これ何のゲーム？"),
  )
}

///|
test "拾い上げに入らなかったコメントと、相乗りしただけのコメントは出さない" {
  assert_eq(@lib.render_pickup_line(entry(Chatter, Judged, None)), None)
  assert_eq(@lib.render_pickup_line(entry(Reaction, Early, None)), None)
  assert_eq(
    @lib.render_pickup_line(entry(Question, Inherited, Some(3), priority=1.2)),
    None,
  )
}

///|
test "種類には日本語のラベルがある" {
  assert_eq(@lib.Kind::FirstTime.label(), "初見")
  assert_eq(@lib.Kind::Unjudged.label(), "未判定")
}
