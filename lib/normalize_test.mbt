///|
test "全角英数と記号を半角に、大文字を小文字にそろえる" {
  assert_eq(@lib.normalize("ＧＧ　ＷＰ"), "g wp")
  assert_eq(@lib.normalize("Nice"), "nice")
}

///|
test "半角カナは全角カナにそろえる（濁点・半濁点も合成する）" {
  assert_eq(@lib.unify_width("ﾅｲｽ"), "ナイス")
  assert_eq(@lib.unify_width("ｶﾞﾝﾊﾞ ﾊﾟﾝ"), "ガンバ パン")
}

///|
test "前後の空白を除き、連続した空白は 1 個にする" {
  assert_eq(
    @lib.normalize("  こんにちは   みなさん \n"),
    "こんにちは みなさん",
  )
}

///|
test "同じ文字の連続は 1 文字に圧縮する" {
  assert_eq(@lib.compress_runs("wwww"), "w")
  assert_eq(@lib.compress_runs("8888"), "8")
  assert_eq(@lib.compress_runs("！！！"), "！")
  assert_eq(@lib.compress_runs("草草草"), "草")
  assert_eq(@lib.compress_runs("うおおおお"), "うお")
}

///|
test "数字の並びは全桁が同じときだけ圧縮する（1000 を 10 にしない）" {
  assert_eq(@lib.compress_runs("1000円"), "1000円")
  assert_eq(@lib.compress_runs("2255"), "2255")
  assert_eq(@lib.compress_runs("888 1000"), "8 1000")
}

///|
test "末尾の記号ゆれを除く" {
  assert_eq(@lib.normalize("草！！"), "草")
  assert_eq(@lib.normalize("かわいい〜〜"), "かわい")
  assert_eq(@lib.normalize("すげーーー"), "すげ")
  assert_eq(@lib.normalize("これ何？"), "これ何")
  assert_eq(@lib.normalize("おつ。"), "おつ")
}

///|
test "日本語の直後の笑いの w は除くが、w だけ・英単語の末尾は残す" {
  assert_eq(@lib.normalize("それはないわwww"), "それはないわ")
  assert_eq(@lib.normalize("ｗｗｗｗ"), "w")
  assert_eq(@lib.normalize("draw"), "draw")
}

///|
test "記号だけのコメントは空にせず圧縮した形で残す" {
  assert_eq(@lib.normalize("？？？"), "?")
  assert_eq(@lib.normalize("！？"), "!?")
}

///|
test "YouTube の :emoji: 記法はトークンとして保持し、連続は 1 個にする" {
  assert_eq(
    @lib.normalize(":face-blue-smiling::face-blue-smiling:"),
    ":face-blue-smiling:",
  )
  assert_eq(@lib.normalize("草 :YTgg: :YTgg:"), "草 :YTgg:")
}

///|
test "Twitch のエモート名は大文字小文字も連続文字もそのまま保持する" {
  assert_eq(
    @lib.normalize("PogChamp PogChamp", emotes=["PogChamp"]),
    "PogChamp",
  )
  assert_eq(
    @lib.normalize("やったー xqcLL", emotes=["xqcLL"]),
    "やった xqcLL",
  )
}

///|
test "絵文字はそのまま残り、連続は 1 個になる" {
  assert_eq(@lib.normalize("👏👏👏"), "👏")
  assert_eq(@lib.normalize("すごい🎉🎉"), "すごい🎉")
}

///|
test "トークン列ではスタンプと文字を区別できる" {
  assert_eq(@lib.normalize_tokens("草 :YTgg:"), [Text("草"), Emote(":YTgg:")])
  assert_eq(@lib.normalize_tokens("   "), [])
}

///|
test "カタカナはひらがなにそろえる（ナイス と ないす、カワイイ と かわいい を同じ束にする）" {
  assert_eq(@lib.normalize("ナイス"), @lib.normalize("ないす"))
  assert_eq(@lib.normalize("カワイイ"), @lib.normalize("かわいい"))
  assert_eq(@lib.normalize("ｷﾀｰｰ"), @lib.normalize("きたー"))
  // ヴ・ヵ・ヶ など、ひらがなに対応が無い・使われない文字はそのまま
  assert_eq(@lib.normalize("ヴァイオリン"), "ヴぁいおりん")
}

///|
test "Comment のチャンネルは省略すると空" {
  assert_eq(@lib.Comment::new("stdin:a", "hi").channel, "")
  assert_eq(@lib.Comment::new("twitch:1", "hi", channel="ch").channel, "ch")
}
