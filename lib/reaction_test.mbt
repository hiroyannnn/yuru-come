///|
fn early(text : String, emotes? : Array[String] = []) -> Bool {
  @lib.ReactionRules::new().is_reaction(text, emotes~)
}

///|
test "既定辞書にある短い反応は Jev を呼ばずに reaction と決める" {
  for
    text in [
      "草", "www", "ｗｗｗｗｗ", "8888", "かわいい", "うおおおお",
      "ナイス", "GG", "おつ〜",
    ] {
    assert_true(early(text), msg=text)
  }
}

///|
test "草の言い換えも辞書で拾う" {
  for text in ["大草原", "くさ", "草生える", "kusa"] {
    assert_true(early(text), msg=text)
  }
}

///|
test "辞書は原文ではなく正規化した形で照合する" {
  assert_true(early("かわいいいいい！！！"))
  assert_true(early("ＮＩＣＥ"))
  assert_true(early("ﾅｲｽ"))
}

///|
test "スタンプだけ・記号だけ・数字だけ・絵文字だけのコメントは reaction" {
  assert_true(early("PogChamp PogChamp", emotes=["PogChamp"]))
  assert_true(early(":face-blue-smiling::face-blue-smiling:"))
  assert_true(early("！？"))
  assert_true(early("……"))
  assert_true(early("👏👏👏"))
  assert_true(early("1"))
}

///|
test "正規化して 1 文字になるコメントは reaction" {
  assert_true(early("え"))
  assert_true(early("神"))
  assert_true(early("は？"))
  assert_true(early("えええええ？"))
}

///|
test "同じ文字を 3 回以上伸ばした短い叫びは辞書になくても reaction" {
  assert_true(early("きたあああ"))
  assert_true(early("やばああああい"))
  assert_true(early("ひえええ"))
  // 伸ばしていても長いコメントは対象外
  assert_false(
    early("そこはもっと右に行ったほうがいいよおおお"),
  )
}

///|
test "短いだけでは reaction にしない（なぜ・やめて を落とさない）" {
  assert_false(early("なぜ"))
  assert_false(early("やめて"))
  assert_false(early("みぎ"))
}

///|
test "短くても漢字を含む語は辞書になければ Jev に回す（初見 を落とさない）" {
  assert_false(early("初見"))
  assert_false(early("音量"))
}

///|
test "疑問符つきの 2 文字以上のコメントは短くても Jev に回す" {
  assert_false(early("なに？"))
  assert_false(early("だれ?"))
}

///|
test "中身のあるコメントは reaction にしない" {
  assert_false(
    early(
      "それ原油じゃなくて重油のタンクにつないでない？",
    ),
  )
  assert_false(early("初見です！よろしくお願いします"))
  assert_false(early("音が出てないよ"))
  assert_false(early("草 でもそのルートは遠回りだと思う"))
}

///|
test "辞書は設定で追加できる" {
  let rules = @lib.ReactionRules::new(extra_words=[
    "てぇてぇ", "助かる！",
  ])
  assert_true(rules.is_reaction("てぇてぇ"))
  assert_true(rules.is_reaction("助かる"))
  assert_false(@lib.ReactionRules::new().is_reaction("配信助かる"))
}

///|
test "空のコメントは reaction（Jev に投げない）" {
  assert_true(early("   "))
}
