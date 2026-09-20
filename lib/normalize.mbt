///|
/// 正規化後のトークン。スタンプは中身をいじらずに保持する。
pub(all) enum Token {
  /// 正規化済みの文字列
  Text(String)
  /// スタンプ（Twitch のエモート名、YouTube の `:emoji:`）。原文のまま
  Emote(String)
} derive(Debug, Eq)

///|
/// 半角カナ U+FF61〜U+FF9D に対応する全角文字。
const HALFWIDTH_KANA_TABLE : String = "。「」、・ヲァィゥェォャュョッーアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン"

///|
/// 濁点を付けられる全角カナ（コードポイント +1 が濁音）。
const DAKUTEN_BASE : String = "カキクケコサシスセソタチツテトハヒフヘホ"

///|
/// 半濁点を付けられる全角カナ（コードポイント +2 が半濁音）。
const HANDAKUTEN_BASE : String = "ハヒフヘホ"

///|
/// 全角英数・記号を半角に、全角空白を半角空白に、半角カナを全角カナにそろえる。
pub fn unify_width(text : String) -> String {
  let kana = HALFWIDTH_KANA_TABLE.to_array()
  let out : Array[Char] = []
  for c in text {
    let code = c.to_int()
    if code >= 0xFF01 && code <= 0xFF5E {
      out.push((code - 0xFEE0).unsafe_to_char())
    } else if code == 0x3000 {
      out.push(' ')
    } else if code >= 0xFF61 && code <= 0xFF9D {
      out.push(kana[code - 0xFF61])
    } else if code == 0xFF9E || code == 0xFF9F {
      match (out.last(), code) {
        (Some('ウ'), 0xFF9E) => out[out.length() - 1] = 'ヴ'
        (Some(prev), 0xFF9E) if DAKUTEN_BASE.contains_char(prev) =>
          out[out.length() - 1] = (prev.to_int() + 1).unsafe_to_char()
        (Some(prev), 0xFF9F) if HANDAKUTEN_BASE.contains_char(prev) =>
          out[out.length() - 1] = (prev.to_int() + 2).unsafe_to_char()
        (_, 0xFF9E) => out.push('゛')
        _ => out.push('゜')
      }
    } else {
      out.push(c)
    }
  }
  String::from_array(out)
}

///|
/// 同じ文字の連続を 1 文字に圧縮する（`wwww`→`w`、`草草草`→`草`）。
/// 数字の並びは全桁が同じとき（`8888`）だけ圧縮し、`1000` のような数値は壊さない。
pub fn compress_runs(text : String) -> String {
  let chars = text.to_array()
  let out : Array[Char] = []
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if is_digit(c) {
      let mut end = i
      let mut uniform = true
      while end < chars.length() && is_digit(chars[end]) {
        if chars[end] != c {
          uniform = false
        }
        end += 1
      }
      if uniform {
        out.push(c)
      } else {
        for k in i..<end {
          out.push(chars[k])
        }
      }
      i = end
    } else {
      out.push(c)
      while i < chars.length() && chars[i] == c {
        i += 1
      }
    }
  }
  String::from_array(out)
}

///|
fn chars_to_string(chars : ArrayView[Char]) -> String {
  let out = StringBuilder()
  for c in chars {
    out.write_char(c)
  }
  out.to_string()
}

///|
/// 空白（全角空白を含む）で語に分ける。空の語は返さない。
fn split_words(text : String) -> Array[String] {
  let words : Array[String] = []
  let current = StringBuilder()
  for c in text {
    if is_space(c) {
      if !current.is_empty() {
        words.push(current.to_string())
        current.reset()
      }
    } else {
      current.write_char(c)
    }
  }
  if !current.is_empty() {
    words.push(current.to_string())
  }
  words
}

///|
fn is_digit(c : Char) -> Bool {
  c is ('0'..='9')
}

///|
fn is_space(c : Char) -> Bool {
  c is (' ' | '\t' | '\r' | '\n' | '　')
}

///|
/// 末尾の記号ゆれ（unify_width 後の形）。
const TRAILING_MARKS : String = "!?.,~。、…‥ー〜・"

///|
/// 末尾の記号ゆれと、日本語の直後の笑いの `w` を除く。全部消えてしまうなら元のまま返す。
fn strip_trailing_marks(text : String) -> String {
  let chars = text.to_array()
  let mut end = chars.length()
  while end > 0 {
    let c = chars[end - 1]
    if TRAILING_MARKS.contains_char(c) {
      end -= 1
    } else if c == 'w' && end >= 2 && chars[end - 2].to_int() > 0x7F {
      end -= 1
    } else {
      break
    }
  }
  if end == 0 {
    text
  } else {
    chars_to_string(chars[:end])
  }
}

///|
fn to_ascii_lower(text : String) -> String {
  let out = StringBuilder()
  for c in text {
    if c is ('A'..='Z') {
      out.write_char((c.to_int() + 32).unsafe_to_char())
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn normalize_text(text : String) -> String {
  unify_width(text) |> to_ascii_lower |> compress_runs |> strip_trailing_marks
}

///|
/// `:name:`（英数字と `_` `-`）の終わりの位置を返す。`start` は先頭の `:` の位置。
fn emoji_code_end(chars : Array[Char], start : Int) -> Int? {
  let mut i = start + 1
  while i < chars.length() {
    let c = chars[i]
    if c == ':' {
      return if i > start + 1 { Some(i + 1) } else { None }
    }
    guard c is ('a'..='z' | 'A'..='Z' | '0'..='9' | '_' | '-') else {
      return None
    }
    i += 1
  }
  None
}

///|
/// 空白を含まない 1 語を、`:emoji:` とそれ以外に分ける（未正規化）。
fn split_word(word : String, emotes : Array[String]) -> Array[Token] {
  if emotes.contains(word) {
    return [Emote(word)]
  }
  let chars = word.to_array()
  let tokens : Array[Token] = []
  let mut text_start = 0
  let mut i = 0
  while i < chars.length() {
    if chars[i] == ':' && emoji_code_end(chars, i) is Some(end) {
      if i > text_start {
        tokens.push(Text(chars_to_string(chars[text_start:i])))
      }
      tokens.push(Emote(chars_to_string(chars[i:end])))
      text_start = end
      i = end
    } else {
      i += 1
    }
  }
  if chars.length() > text_start {
    tokens.push(Text(chars_to_string(chars[text_start:])))
  }
  tokens
}

///|
/// コメントを正規化したトークン列にする。
///
/// - 文字: 全角半角と大文字小文字の統一、空白の整理、同一文字の連続圧縮、末尾の記号ゆれの除去
/// - スタンプ: `emotes`（Twitch のエモート名）に一致する語と `:emoji:` 記法は原文のまま保持
/// - 同じスタンプの連続は 1 個にする
pub fn normalize_tokens(
  text : String,
  emotes? : Array[String] = [],
) -> Array[Token] {
  let raw : Array[Token] = []
  for word in split_words(text) {
    for token in split_word(word, emotes) {
      match (raw.last(), token) {
        // 空白で区切られた文字どうしは 1 個の空白でつなぐ
        (Some(Text(prev)), Text(next)) =>
          raw[raw.length() - 1] = Text("\{prev} \{next}")
        _ => raw.push(token)
      }
    }
  }
  let tokens : Array[Token] = []
  for token in raw {
    let token = match token {
      Text(t) => Token::Text(normalize_text(t))
      Emote(_) => token
    }
    if tokens.last() is Some(last) && last == token && token is Emote(_) {
      continue
    }
    tokens.push(token)
  }
  tokens
}

///|
/// 束ねのキーになる正規化文字列。トークンを 1 個の空白でつないだもの。
pub fn normalize(text : String, emotes? : Array[String] = []) -> String {
  normalize_tokens(text, emotes~)
  .map(token => {
    match token {
      Text(t) => t
      Emote(e) => e
    }
  })
  .join(" ")
}
