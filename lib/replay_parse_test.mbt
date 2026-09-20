///|
test "時刻ms<TAB>参加者ID<TAB>発言 の行を、時刻と Comment にする" {
  assert_eq(
    @lib.parse_replay_line("1500\talice\tこれ何のゲーム？"),
    Some(
      (
        1500L,
        @lib.Comment::new(
          "replay:alice",
          "これ何のゲーム？",
          author="alice",
        ),
      ),
    ),
  )
}

///|
test "発言に TAB が含まれていても 3 列目以降をそのまま本文にする" {
  assert_true(
    @lib.parse_replay_line("0\tbob\ta\tb") is Some((0L, { text: "a\tb", .. })),
  )
}

///|
test "空行、# で始まるコメント行、列が足りない行、時刻が数値でない行は読み飛ばす" {
  assert_eq(@lib.parse_replay_line(""), None)
  assert_eq(@lib.parse_replay_line("# 反応の波"), None)
  assert_eq(@lib.parse_replay_line("1500\talice"), None)
  assert_eq(@lib.parse_replay_line("soon\talice\t草"), None)
  assert_eq(@lib.parse_replay_line("1500\talice\t   "), None)
}

///|
test "倍速再生での待ち時間は、行どうしの時刻の差を速度で割ったもの" {
  assert_eq(@lib.replay_delay_ms(1000, 3000, 1.0), 2000)
  assert_eq(@lib.replay_delay_ms(1000, 3000, 10.0), 200)
  // 時刻が逆行していても待ち時間は負にならない
  assert_eq(@lib.replay_delay_ms(3000, 1000, 10.0), 0)
  // 速度が 0 以下なら待たない
  assert_eq(@lib.replay_delay_ms(1000, 3000, 0.0), 0)
}
