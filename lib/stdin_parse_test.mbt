///|
test "参加者ID<TAB>発言 の行を Comment にする（ID には stdin: を付け、投稿者は ID）" {
  assert_eq(
    @lib.parse_stdin_line("alice\t初見です", at=123),
    Some(
      @lib.Comment::new("stdin:alice", "初見です", author="alice", at=123),
    ),
  )
}

///|
test "TAB が無い行は匿名参加者の発言として扱う（ID は差し替え可能）" {
  assert_eq(
    @lib.parse_stdin_line("うーん迷う", at=1),
    Some(
      @lib.Comment::new("stdin:anon", "うーん迷う", author="anon", at=1),
    ),
  )
  assert_true(
    @lib.parse_stdin_line("うーん迷う", at=1, anonymous_id="me")
    is Some({ participant_id: "stdin:me", .. }),
  )
}

///|
test "空行・空白だけの行・末尾改行は無視または除去する" {
  assert_eq(@lib.parse_stdin_line("", at=1), None)
  assert_eq(@lib.parse_stdin_line("   \n", at=1), None)
  assert_true(
    @lib.parse_stdin_line("bob\t音が出てないよ\r\n", at=1)
    is Some({ text: "音が出てないよ", .. }),
  )
}

///|
test "source を変えると ID のプレフィックスが変わる（TikTok ブリッジ用）" {
  assert_true(
    @lib.parse_stdin_line("dave\tこんにちは", at=1, source="tiktok")
    is Some({ participant_id: "tiktok:dave", .. }),
  )
}
