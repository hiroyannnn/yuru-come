///|
/// LLM に渡す「いまの空気」の入力。
pub(all) struct SummaryPrompt {
  system : String
  user : String
} derive(Debug, Eq)

///|
/// 画面に出す「いまの空気」の一文。
pub(all) struct Summary {
  text : String
  /// `llm`（OpenAI が書いた）か `template`（数字を文に並べただけ）
  source : String
  at : Int64
} derive(Debug, Eq, ToJson)

///|
/// LLM の要約をテンプレートに戻すまでの時間（ミリ秒）。
pub const SUMMARY_STALE_MS : Int64 = 120_000

///|
/// 一文の長さの上限（文字）。これを超えたら切る。
pub const SUMMARY_MAX_CHARS : Int = 80

///|
/// 種類ごとの件数を「指摘 1、初見 1」の形にする。反応と未判定は数えない。
fn kind_counts_text(by_kind : Map[String, Int]) -> String {
  let parts : Array[String] = []
  for kind in jev_kinds {
    if by_kind.get(kind.key()) is Some(n) && n > 0 {
      parts.push("\{kind.label()} \{n}")
    }
  }
  parts.join("、")
}

///|
/// 一文に載せる束の数の上限。
const SUMMARY_BUNDLE_LIMIT : Int = 3

///|
fn bundles_text(bundles : Array[BundleSummary]) -> String {
  let top = if bundles.length() > SUMMARY_BUNDLE_LIMIT {
    bundles[:SUMMARY_BUNDLE_LIMIT]
  } else {
    bundles[:]
  }
  top.map(b => "「\{b.representative}」×\{b.count}").join("、")
}

///|
/// LLM を使わない一文。数字を文に並べるだけ。
pub fn template_summary(state : EngineState) -> String {
  let mood = state.mood_short
  if mood.total == 0 {
    return "この 30 秒はコメントがありません。"
  }
  let parts : Array[String] = []
  if !state.bundles.is_empty() {
    parts.push("\{bundles_text(state.bundles)} が続いています。")
  }
  let kinds = kind_counts_text(mood.by_kind)
  if !kinds.is_empty() {
    parts.push("\{kinds}。")
  }
  parts.push("30 秒で \{mood.total} 件・\{mood.participants} 人。")
  parts.join("")
}

///|
pub const SUMMARY_SYSTEM_PROMPT : String = "あなたはライブ配信のチャット欄を横で見ている助手です。渡された情報だけを使って、配信者がいまチャットで起きていることを一目で分かるように、日本語の一文（60 字以内）で伝えてください。コメントに無いことは書かない。前置きや引用符は付けず、文だけを返す。"

///|
/// LLM への入力。文脈、束、種類の分布、直近の中身のあるコメント（反応・荒らし・未判定を除く）を並べる。
pub fn summary_prompt(
  state : EngineState,
  recent_limit? : Int = 12,
) -> SummaryPrompt {
  let lines : Array[String] = []
  if !state.context.is_empty() {
    lines.push("配信の文脈: \{state.context}")
  }
  let mood = state.mood_short
  lines.push(
    "直近 30 秒: \{mood.total} 件、\{mood.participants} 人が発言",
  )
  if !state.bundles.is_empty() {
    lines.push("まとまった反応: \{bundles_text(state.bundles)}")
  }
  let kinds = kind_counts_text(mood.by_kind)
  if !kinds.is_empty() {
    lines.push("種類: \{kinds}")
  }
  let recent : Array[String] = []
  for entry in state.flow {
    guard recent.length() < recent_limit else { break }
    match entry.kind {
      Reaction | Unjudged | Abuse => continue
      kind =>
        recent.push(
          "[\{kind.label()}] \{entry.comment.author}: \{entry.comment.text}",
        )
    }
  }
  if !recent.is_empty() {
    lines.push("直近のコメント（新しい順）:")
    for line in recent {
      lines.push(line)
    }
  }
  { system: SUMMARY_SYSTEM_PROMPT, user: lines.join("\n"), }
}

///|
/// LLM を呼ぶ価値があるか。前回の要約のあとに新しいコメントが来ていて、窓が空でないとき。
pub fn summary_needed(state : EngineState, last_entry_id~ : Int) -> Bool {
  state.mood_short.total > 0 &&
  state.flow is [newest, ..] &&
  newest.id != last_entry_id
}

///|
/// 返ってきた文を整える。前後の空白・引用符・「要約:」のような前置きを除き、最初の行だけにして、長すぎれば切る。
pub fn clean_summary(text : String) -> String {
  let first_line = match text.trim(chars=" \t\r\n　").find("\n") {
    Some(i) => text.trim(chars=" \t\r\n　")[:i].to_owned()
    None => text.trim(chars=" \t\r\n　").to_owned()
  }
  let mut line = first_line.trim(chars=" \t　\"'「」『』“”").to_owned()
  for prefix in ["要約:", "要約：", "Summary:"] {
    if line.has_prefix(prefix) {
      line = line[prefix.length():].trim(chars=" 　").to_owned()
    }
  }
  if line.char_length() > SUMMARY_MAX_CHARS {
    let cut = line
      .offset_of_nth_char(SUMMARY_MAX_CHARS)
      .unwrap_or(line.length())
    "\{line[:cut]}…"
  } else {
    line
  }
}
