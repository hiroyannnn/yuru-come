// Twitch のチャットに匿名（justinfan、読み取り専用）で WebSocket 接続する。
// 切れたら 1 秒、2 秒、4 秒…最大 60 秒の間隔でつなぎ直す。
// onData(text) は受け取ったデータ（複数行のこともある）を渡し、返り値の文字列（PONG など）を送り返す。
"use strict";

const URL_IRC = "wss://irc-ws.chat.twitch.tv:443";

export function connectTwitch(channel, { loginLines, onData, onStatus }) {
  let failures = 0;
  let socket = null;
  let stopped = false;

  function open() {
    const nick = `justinfan${Math.floor(10000 + Math.random() * 89999)}`;
    const openedAt = Date.now();
    onStatus({ ok: false, text: `#${channel} に接続しています…` });
    socket = new WebSocket(URL_IRC);
    socket.onopen = () => {
      for (const line of loginLines(nick, channel).split("\r\n")) {
        if (line) socket.send(line);
      }
    };
    socket.onmessage = (event) => {
      const text = String(event.data);
      if (/ JOIN #/.test(text) || / 001 /.test(text)) {
        onStatus({ ok: true, text: `#${channel} を読んでいます` });
      }
      // Twitch がつなぎ直しを求めてきたら閉じる（onclose で再接続する）
      if (/^:tmi\.twitch\.tv RECONNECT/m.test(text)) {
        socket.close();
        return;
      }
      const reply = onData(text);
      if (reply) {
        for (const line of reply.split("\r\n")) {
          if (line) socket.send(line);
        }
      }
    };
    socket.onclose = () => {
      if (stopped) return;
      // 1 分以上もった接続のあとはすぐつなぎ直す
      if (Date.now() - openedAt >= 60_000) failures = 0;
      const delay = Math.min(1000 * 2 ** failures, 60_000);
      failures += 1;
      onStatus({ ok: false, text: `切断されました。${Math.round(delay / 1000)} 秒後につなぎ直します` });
      setTimeout(open, delay);
    };
    socket.onerror = () => socket.close();
  }

  open();
  return () => {
    stopped = true;
    if (socket) socket.close();
  };
}
