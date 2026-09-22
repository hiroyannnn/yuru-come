///|
pub const TWITCH_IRC_HOST : String = "irc.chat.twitch.tv"

///|
pub const TWITCH_IRC_TLS_PORT : Int = 6697

///|
pub const TWITCH_IRC_PLAIN_PORT : Int = 6667

///|
/// Twitch チャットを匿名ユーザー（`justinfan<数字>`、PASS 不要）で読み取り専用購読する Source。
/// TLS（6697）を優先し、失敗したら平文（6667）にフォールバックする。
/// 接続が切れたら待ち時間を倍にしながら再接続し続ける（1 秒から最大 60 秒。60 秒以上もった接続のあとは 1 秒に戻る）。
pub struct TwitchSource {
  channel : String
  nick : String
}

///|
pub fn TwitchSource::new(channel : String, nick? : String) -> TwitchSource {
  let nick = match nick {
    Some(n) => n
    None => "justinfan\{@async.now() % 100000}"
  }
  { channel: channel.trim_start(chars="#").to_owned(), nick, }
}

///|
pub impl @lib.Source for TwitchSource with fn run(self, submit) {
  let mut failures = 0
  while true {
    let started = @async.now()
    self.connect_once(submit) catch {
      err => @runtime.log("twitch: #\{self.channel} の接続に失敗: \{err}")
    }
    if @lib.connection_was_healthy(connected_ms=@async.now() - started) {
      failures = 0
    }
    let delay = @lib.reconnect_delay_ms(failures)
    failures += 1
    @runtime.log(
      "twitch: #\{self.channel} に \{delay}ms 後に再接続します",
    )
    @async.sleep(delay)
  }
}

///|
/// 1 回つないで、切れるまで読む。
async fn TwitchSource::connect_once(
  self : TwitchSource,
  submit : async (@lib.Comment) -> Unit,
) -> Unit {
  let tcp = @socket.Tcp::connect_to_host(
    TWITCH_IRC_HOST,
    port=TWITCH_IRC_TLS_PORT,
  )
  let tls = @tls.Tls::client(tcp, host=TWITCH_IRC_HOST) catch {
    err => {
      tcp.close()
      @runtime.log(
        "twitch: TLS 接続に失敗したので平文 \{TWITCH_IRC_PLAIN_PORT} 番で再接続します: \{err}",
      )
      let plain = @socket.Tcp::connect_to_host(
        TWITCH_IRC_HOST,
        port=TWITCH_IRC_PLAIN_PORT,
      )
      defer plain.close()
      return self.chat_loop(plain, submit)
    }
  }
  defer tls.close()
  self.chat_loop(tls, submit)
}

///|
/// ログインして PRIVMSG を読み続ける。接続が切れたら戻る。
async fn[C : @io.Reader + @io.Writer] TwitchSource::chat_loop(
  self : TwitchSource,
  conn : C,
  submit : async (@lib.Comment) -> Unit,
) -> Unit {
  for line in @lib.twitch_login_lines(self.nick, self.channel) {
    @io.Writer::write(conn, "\{line}\r\n")
  }
  @runtime.log(
    "twitch: #\{self.channel} に \{self.nick} として接続しました",
  )
  while @io.Reader::read_until(conn, "\r\n") is Some(line) {
    match @lib.parse_irc_line(line) {
      Ping(payload) => @io.Writer::write(conn, "\{@lib.pong_line(payload)}\r\n")
      Chat(comment) => submit(comment)
      Other(_) => ()
    }
  }
  @runtime.log("twitch: #\{self.channel} の接続が切れました")
}
