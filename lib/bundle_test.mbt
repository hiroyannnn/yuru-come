///|
fn comment_by(who : String, text : String) -> @lib.Comment {
  @lib.Comment::new(@lib.participant_id("test", who), text)
}

///|
/// 原文を正規化したキーで束ねる（エンジンと同じ使い方）。
fn add_text(
  bundler : @lib.Bundler,
  who : String,
  text : String,
  now : Int64,
) -> @lib.BundleHit {
  bundler.add(@lib.normalize(text), comment_by(who, text), now)
}

///|
test "正規化後に同じになるコメントは 1 つの束になり、件数と参加者数を数える" {
  let bundler = @lib.Bundler::new()
  assert_eq(add_text(bundler, "a", "草", 1000).count, 1)
  assert_eq(add_text(bundler, "b", "草www", 2000).count, 2)
  let hit = add_text(bundler, "a", "草草草！", 3000)
  assert_eq(hit.count, 3)
  assert_eq(hit.key, "草")
  let summaries = bundler.summaries(3000)
  assert_eq(summaries.length(), 1)
  assert_eq(summaries[0].count, 3)
  assert_eq(summaries[0].participants, 2)
  assert_eq(summaries[0].last_at, 3000)
}

///|
test "束の代表テキストはいちばん短い原文" {
  let bundler = @lib.Bundler::new()
  add_text(bundler, "a", "かわいいいいいい！！", 0) |> ignore
  add_text(bundler, "b", "かわいい", 10) |> ignore
  add_text(bundler, "c", "かわいいー", 20) |> ignore
  assert_eq(bundler.summaries(20)[0].representative, "かわいい")
}

///|
test "時間窓を過ぎた分は件数から外れ、空になった束は消える" {
  let bundler = @lib.Bundler::new(
    config=@lib.BundleConfig::new(window_ms=30000),
  )
  add_text(bundler, "a", "8888", 0) |> ignore
  add_text(bundler, "b", "888", 20000) |> ignore
  assert_eq(bundler.summaries(20000)[0].count, 2)
  // 0ms の分が窓から外れる
  assert_eq(add_text(bundler, "c", "88888", 40000).count, 2)
  assert_eq(bundler.summaries(100000, min_count=1), [])
  // 消えたあとに来た同じ反応は新しい束の 1 件目
  assert_eq(add_text(bundler, "d", "8888", 100000).count, 1)
}

///|
test "短いコメントは類似度が閾値以上なら同じ束にする" {
  let bundler = @lib.Bundler::new()
  add_text(bundler, "a", "おめでとうございます", 0) |> ignore
  let hit = add_text(bundler, "b", "おめでとおございます", 10)
  assert_eq(hit.count, 2)
  assert_eq(hit.key, "おめでとうございます")
}

///|
test "既定の設定では、出だしが同じだけの別の質問を束ねない" {
  let bundler = @lib.Bundler::new()
  add_text(bundler, "a", "これ何のゲーム？", 0) |> ignore
  assert_eq(add_text(bundler, "b", "これ何の曲？", 10).count, 1)
}

///|
test "長いコメントは似ていても完全一致でなければ束ねない" {
  let bundler = @lib.Bundler::new(
    config=@lib.BundleConfig::new(fuzzy_max_len=12),
  )
  add_text(
    bundler, "a", "その武器は強化してから行ったほうがいいと思う",
    0,
  )
  |> ignore
  assert_eq(
    add_text(
      bundler, "b", "その防具は強化してから行ったほうがいいと思う",
      10,
    ).count,
    1,
  )
  assert_eq(
    add_text(
      bundler, "c", "その武器は強化してから行ったほうがいいと思う！",
      20,
    ).count,
    2,
  )
}

///|
test "閾値は設定で変えられる" {
  let bundler = @lib.Bundler::new(config=@lib.BundleConfig::new(threshold=0.7))
  add_text(bundler, "a", "かわいい", 0) |> ignore
  assert_eq(add_text(bundler, "b", "かわいいね", 10).count, 2)
}

///|
test "類似度を Jaro-Winkler に切り替えられる" {
  let strict = @lib.Bundler::new()
  add_text(strict, "a", "かわいい", 0) |> ignore
  assert_eq(add_text(strict, "b", "かわいいね", 10).count, 1)
  let loose = @lib.Bundler::new(
    config=@lib.BundleConfig::new(metric=JaroWinkler),
  )
  add_text(loose, "a", "かわいい", 0) |> ignore
  assert_eq(add_text(loose, "b", "かわいいね", 10).count, 2)
}

///|
test "束の一覧は件数の多い順で、件数の下限と個数の上限を指定できる" {
  let bundler = @lib.Bundler::new()
  for i in 0..<3 {
    add_text(bundler, "u\{i}", "草", i.to_int64()) |> ignore
  }
  for i in 0..<5 {
    add_text(bundler, "u\{i}", "8888", i.to_int64()) |> ignore
  }
  add_text(bundler, "x", "初見です", 10) |> ignore
  let top = bundler.summaries(10)
  assert_eq(top.map(s => (s.representative, s.count)), [("8888", 5), ("草", 3)])
  assert_eq(bundler.summaries(10, limit=1).length(), 1)
  assert_eq(bundler.summaries(10, min_count=1).length(), 3)
}

///|
test "完全一致で入ったか、類似度で入ったかを区別できる" {
  let bundler = @lib.Bundler::new()
  assert_true(add_text(bundler, "a", "おめでとうございます", 0).exact)
  assert_true(
    add_text(bundler, "b", "おめでとうございます！！", 1).exact,
  )
  assert_false(
    add_text(bundler, "c", "おめでとおございます", 2).exact,
  )
}
