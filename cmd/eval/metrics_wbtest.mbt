///|
test "評価セットの行を 正解の kind・拾うべきか・コメント に分ける" {
  assert_eq(
    parse_eval_line("question\t1\tこれ何のゲーム？"),
    Some({ kind: Question, pickup: true, text: "これ何のゲーム？", }),
  )
  assert_eq(
    parse_eval_line("reaction\t0\t草"),
    Some({ kind: Reaction, pickup: false, text: "草", }),
  )
}

///|
test "コメント行・空行・知らない kind・列が足りない行は読み飛ばす" {
  assert_eq(parse_eval_line("# 説明"), None)
  assert_eq(parse_eval_line(""), None)
  assert_eq(parse_eval_line("banana\t1\tx"), None)
  assert_eq(parse_eval_line("question\t1"), None)
}

///|
test "混同行列から正解率を出す" {
  let confusion = Confusion::new()
  confusion.add(Question, Question)
  confusion.add(Question, Question)
  confusion.add(Question, Request)
  confusion.add(Trouble, Correction)
  assert_eq(confusion.total(), 4)
  assert_eq(confusion.correct(), 2)
  assert_eq(confusion.accuracy(), 0.5)
  assert_eq(confusion.count(Question, Request), 1)
  assert_eq(confusion.count(Trouble, Trouble), 0)
}

///|
test "混同行列は出てきた kind だけを行と列にした表にする" {
  let confusion = Confusion::new()
  confusion.add(Question, Question)
  confusion.add(Trouble, Correction)
  assert_eq(
    confusion.render(),
    (
      #|| 正解＼判定 | question | correction | trouble |
      #|| --- | --- | --- | --- |
      #|| question | 1 | 0 | 0 |
      #|| trouble | 0 | 1 | 0 |
    ),
  )
}

///|
test "適合率と再現率" {
  let score = PickupScore::new()
  score.add(expected=true, predicted=true)
  score.add(expected=true, predicted=true)
  score.add(expected=true, predicted=false)
  score.add(expected=false, predicted=true)
  score.add(expected=false, predicted=false)
  assert_eq(score.precision(), 2.0 / 3.0)
  assert_eq(score.recall(), 2.0 / 3.0)
}

///|
test "拾うと判定したものが無ければ適合率は 0（0 除算しない）" {
  let score = PickupScore::new()
  score.add(expected=true, predicted=false)
  assert_eq(score.precision(), 0.0)
  assert_eq(score.recall(), 0.0)
}

///|
test "所要時間の中央値と 95 パーセンタイル" {
  assert_eq(percentile([400, 100, 300, 200], 50), 200)
  assert_eq(percentile([400, 100, 300, 200], 95), 400)
  assert_eq(percentile([], 50), 0)
}
