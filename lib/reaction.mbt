///|
/// Jev を呼ばずに reaction と決めてよい、短い反応の既定辞書。
/// 照合は正規化後の形で行うので、伸ばし方や全角半角のゆれはここに並べなくてよい。
pub let default_reaction_words : Array[String] = [
  // 笑い・拍手
  "草", "大草原", "草生える", "草はえる", "くさ", "kusa", "w", "笑",
  "爆笑", "わろた", "ワロタ", "lol", "lmao", "lul", "kek", "8", "ぱちぱち",
  "パチパチ",
  // 称賛
   "かわいい", "かわよ", "かっこいい", "すごい", "すご", "すげえ",
  "すげー", "うまい", "うま", "つよい", "つよ", "えらい", "天才",
  "最高", "優勝", "神", "さすが", "ナイス", "ないす", "nice", "gg",
  "ggwp", "gj", "pog", "poggers", "いいね", "尊い", "てえてえ",
  // 驚き・叫び
   "うおおお", "おおお", "きた", "きたー", "キター", "やば", "やばい",
  "えぐ", "えぐい", "まじか", "まじ", "えええ", "ひえ", "こわい",
  "怖い", "あぶない", "危ない", "おしい", "惜しい", "どんまい",
  "ドンマイ", "泣いた", "泣", "f", "ez",
  // 相づち
   "わかる", "それな", "たしかに", "確かに", "なるほど", "ですよね",
  "せやな", "知ってた", "うん", "はい", "へえ", "ほう", "了解",
  "りょ", "おk", "ok",
  // 労い
   "おつ", "おつかれ", "おつかれさま", "お疲れ", "お疲れ様", "たすかる",
  "助かる",
]

///|
/// 叫び（同じ文字を伸ばした短いコメント）とみなす、正規化後の最大文字数。
const SHOUT_MAX_LEN : Int = 4

///|
/// 叫びとみなすのに必要な、原文での同一文字の連続数。
const SHOUT_MIN_RUN : Int = 3

///|
/// 反応の早期判定ルール。長さ・文字種・辞書だけで決める純粋な判定。
pub struct ReactionRules {
  /// 正規化済みの辞書
  words : Map[String, Unit]
}

///|
/// `extra_words` で辞書に語を足せる（正規化してから登録する）。
pub fn ReactionRules::new(extra_words? : Array[String] = []) -> ReactionRules {
  let words : Map[String, Unit] = Map([])
  for word in default_reaction_words {
    words[normalize(word)] = ()
  }
  for word in extra_words {
    words[normalize(word)] = ()
  }
  { words, }
}

///|
/// 言葉として読む文字か（かな・漢字・英字・その他の文字体系）。数字・記号・絵文字は含めない。
fn is_wordish(c : Char) -> Bool {
  let code = c.to_int()
  c is ('a'..='z' | 'A'..='Z') ||
  (code >= 0x00C0 && code <= 0x1FFF) ||
  c == '々' ||
  (code >= 0x3041 && code <= 0x3096) ||
  (code >= 0x30A1 && code <= 0x30FA) ||
  (code >= 0x3400 && code <= 0x9FFF) ||
  (code >= 0xAC00 && code <= 0xD7AF) ||
  (code >= 0xF900 && code <= 0xFAFF)
}

///|
/// 原文に、言葉の文字を `SHOUT_MIN_RUN` 回以上伸ばした箇所があるか。
fn has_elongation(text : String) -> Bool {
  let mut prev : Char? = None
  let mut run = 0
  for c in text {
    if prev is Some(p) && p == c {
      run += 1
    } else {
      prev = Some(c)
      run = 1
    }
    if run >= SHOUT_MIN_RUN && is_wordish(c) {
      return true
    }
  }
  false
}

///|
/// Jev を呼ばずに kind=reaction と決めてよいコメントか。
///
/// 1. 空、スタンプだけ、記号・数字・絵文字だけ
/// 2. 文字の部分が辞書にある、または正規化して 1 文字
/// 3. 同じ文字を伸ばした短い叫び（疑問符つきは除く）
///
/// 「短いだけ」では決めない。「なぜ」「やめて」「初見」は Jev に回す。
pub fn ReactionRules::is_reaction(
  self : ReactionRules,
  text : String,
  emotes? : Array[String] = [],
) -> Bool {
  let parts : Array[String] = []
  for token in normalize_tokens(text, emotes~) {
    if token is Text(t) {
      parts.push(t)
    }
  }
  let words = parts.join(" ")
  if !words.iter().any(is_wordish) {
    return true
  }
  if self.words.contains(words) || words.char_length() == 1 {
    return true
  }
  let asks = text.contains("?") || text.contains("？")
  !asks && words.char_length() <= SHOUT_MAX_LEN && has_elongation(text)
}
