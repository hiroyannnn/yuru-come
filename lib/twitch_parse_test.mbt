///|
test "PRIVMSG（tags 付き）を Comment にする。ID は twitch:<user-id>、投稿者は display-name" {
  let line =
    #|@badge-info=;badges=;color=#FF0000;display-name=Alice;emotes=;tmi-sent-ts=1700000000123;user-id=12345 :alice!alice@alice.tmi.twitch.tv PRIVMSG #somechannel :これ何のゲーム？
  assert_eq(
    @lib.parse_irc_line(line),
    Chat(
      @lib.Comment::new(
        "twitch:12345",
        "これ何のゲーム？",
        author="Alice",
        at=1700000000123,
        channel="somechannel",
      ),
    ),
  )
}

///|
test "tags が無い PRIVMSG は nick を ID と投稿者にし、at は 0" {
  let line = ":bob!bob@bob.tmi.twitch.tv PRIVMSG #ch :初見です"
  assert_eq(
    @lib.parse_irc_line(line),
    Chat(
      @lib.Comment::new(
        "twitch:bob",
        "初見です",
        author="bob",
        channel="ch",
      ),
    ),
  )
}

///|
test "emotes タグの位置からエモート名を取り出す（位置は文字単位、重複は除く）" {
  let line =
    #|@display-name=Carol;emotes=25:0-4,12-16/1902:6-10;user-id=7 :carol!carol@carol.tmi.twitch.tv PRIVMSG #ch :Kappa Keepo Kappa やったー
  guard @lib.parse_irc_line(line) is Chat(comment) else {
    fail("Chat でない")
  }
  assert_eq(comment.emotes, ["Kappa", "Keepo"])
  assert_eq(
    @lib.normalize(comment.text, emotes=comment.emotes),
    "Kappa Keepo Kappa やった",
  )
}

///|
test "絵文字のあとのエモートも位置がずれない" {
  let line =
    #|@emotes=25:3-7;user-id=7 :c!c@c.tmi.twitch.tv PRIVMSG #ch :🎉草 Kappa
  guard @lib.parse_irc_line(line) is Chat(comment) else {
    fail("Chat でない")
  }
  assert_eq(comment.emotes, ["Kappa"])
}

///|
test "壊れた emotes タグは無視する" {
  let line =
    #|@emotes=25:x-y,99-100;user-id=7 :c!c@c.tmi.twitch.tv PRIVMSG #ch :hi
  guard @lib.parse_irc_line(line) is Chat(comment) else {
    fail("Chat でない")
  }
  assert_eq(comment.emotes, [])
}

///|
test "末尾の CRLF は取り除く" {
  let line = ":bob!bob@bob.tmi.twitch.tv PRIVMSG #ch :hi\r\n"
  assert_true(@lib.parse_irc_line(line) is Chat({ text: "hi", .. }))
}

///|
test "PING は payload 付きの Ping になり、pong_line で返答行を作れる" {
  assert_eq(@lib.parse_irc_line("PING :tmi.twitch.tv"), Ping("tmi.twitch.tv"))
  assert_eq(@lib.pong_line("tmi.twitch.tv"), "PONG :tmi.twitch.tv")
}

///|
test "PRIVMSG でも PING でもない行は Other" {
  let line = ":tmi.twitch.tv 001 justinfan123 :Welcome, GLHF!"
  assert_true(@lib.parse_irc_line(line) is Other(_))
  assert_true(@lib.parse_irc_line("") is Other(_))
}

///|
test "twitch_login_lines は匿名ユーザーでの CAP/NICK/JOIN 行を作る" {
  assert_eq(@lib.twitch_login_lines("justinfan777", "SomeChannel"), [
    "CAP REQ :twitch.tv/tags", "NICK justinfan777", "JOIN #somechannel",
  ])
}

///|
test "PRIVMSG の宛先チャンネルを Comment に残す（# は取り除く、大文字は小文字に）" {
  let line = ":bob!bob@bob.tmi.twitch.tv PRIVMSG #SomeChannel :hi"
  guard @lib.parse_irc_line(line) is Chat(comment) else {
    fail("Chat でない")
  }
  assert_eq(comment.channel, "somechannel")
}
