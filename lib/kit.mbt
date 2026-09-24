///|
/// yuru-kit（yuru-poll と共通のチャット取り込み・Jev・.env・QR）の型と関数を、
/// これまでと同じ `@lib.…` の名前で使えるように再エクスポートする。
pub using @kit {
  type Comment,
  trait ChatSource,
  participant_id,
  type IrcMessage,
  parse_irc_line,
  twitch_login_lines,
  pong_line,
  type LiveChatPage,
  type YouTubeError,
  parse_live_chat_id,
  parse_live_chat_page,
  type InnertubeConfig,
  parse_live_chat_page_html,
  parse_get_live_chat,
  innertube_live_chat_url,
  innertube_live_chat_body,
  videos_list_url,
  live_chat_messages_url,
  parse_stdin_line,
  parse_dotenv,
  merge_env,
  qr_svg,
  reconnect_delay_ms,
  connection_was_healthy,
}
