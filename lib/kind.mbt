///|
/// コメントの種類。
pub(all) enum Kind {
  /// 配信者への質問
  Question
  /// リクエスト・提案・指示
  Request
  /// 感想・応援
  Feedback
  /// 指摘・ツッコミ・ミスの報告
  Correction
  /// 挨拶
  Greeting
  /// 初見・初コメを名乗る挨拶
  FirstTime
  /// 配信トラブルの報告
  Trouble
  /// 荒らし・誹謗中傷・スパム
  Abuse
  /// 視聴者同士の雑談・独り言
  Chatter
  /// 短い反応。Jev を呼ばずに早期判定で決まる
  Reaction
  /// 未判定。流量制御で Jev に投げなかった、または判定に失敗した
  Unjudged
} derive(Debug, Eq)

///|
/// Jev に choice の選択肢として渡す 9 種類（criteria の並び順）。
pub let jev_kinds : Array[Kind] = [
  Question,
  Request,
  Feedback,
  Correction,
  Greeting,
  FirstTime,
  Trouble,
  Abuse,
  Chatter,
]

///|
/// JSON と Jev の criteria で使うキー。
pub fn Kind::key(self : Kind) -> String {
  match self {
    Question => "question"
    Request => "request"
    Feedback => "feedback"
    Correction => "correction"
    Greeting => "greeting"
    FirstTime => "first_time"
    Trouble => "trouble"
    Abuse => "abuse"
    Chatter => "chatter"
    Reaction => "reaction"
    Unjudged => "unjudged"
  }
}

///|
pub fn Kind::from_key(key : String) -> Kind? {
  match key {
    "question" => Some(Question)
    "request" => Some(Request)
    "feedback" => Some(Feedback)
    "correction" => Some(Correction)
    "greeting" => Some(Greeting)
    "first_time" => Some(FirstTime)
    "trouble" => Some(Trouble)
    "abuse" => Some(Abuse)
    "chatter" => Some(Chatter)
    "reaction" => Some(Reaction)
    "unjudged" => Some(Unjudged)
    _ => None
  }
}

///|
/// Jev の criteria に渡す説明。先に定義を 1〜2 文で書き、続けてよくある言い回しを具体的に挙げる。
/// eval/ の評価セットで、例だけを並べるより定義を先に書くほうが open-jev（Gemma 3 4B）での正解率が高かった。
/// Reaction / Unjudged は Jev に聞かないので空。
pub fn Kind::description(self : Kind) -> String {
  match self {
    Question =>
      "配信者への質問。配信者に答えてほしいことを尋ねている。「これ何のゲームですか？」「今日は何時までやりますか」「その設定どうやってるんですか」"
    Request =>
      "配信者へのお願い・提案・指示。配信者にしてほしい行動を伝えている。「次は〜をやってほしい」「〜してみて」「先にセーブしたほうがいいですよ」"
    Feedback =>
      "配信や配信者への感想・応援・称賛。「今日の配信おもしろい」「その発想はなかった」「声が落ち着く」「がんばれ」"
    Correction =>
      "配信者のミス・見落とし・言い間違いの指摘やツッコミ。「それ逆じゃない？」「アイテム取り忘れてるよ」「字が違う、〜が正しい」"
    Greeting =>
      "来たとき・帰るときの挨拶が中心のコメント。「こんにちは」「こんばんは、今日も来ました」「わこつ」「そろそろ寝ます、おやすみなさい」"
    FirstTime =>
      "この配信を初めて見に来た・初めてコメントすると名乗っている。「初見です」「初コメです」「はじめまして、切り抜きから来ました」"
    Trouble =>
      "配信の音声や映像が視聴者に正しく届いていないという不具合の報告。「マイクの音が出ていない」「音が途切れる」「画面が止まってる」「映像が乱れてる」「配信が落ちた？」"
    Abuse =>
      "荒らし・誹謗中傷・暴言・スパム・宣伝。配信者や他の視聴者を傷つける言葉、配信と無関係な URL や儲け話の宣伝。「下手くそ、やめちまえ」「消えろ」「きもい」"
    Chatter =>
      "配信者に向けていない、視聴者同士の会話や自分のことの独り言。「〜さんこんばんは」「明日仕事だるい」「ごはん食べてくる」「自分はこのゲーム積んでる」"
    Reaction | Unjudged => ""
  }
}

///|
pub impl ToJson for Kind with fn to_json(self) {
  Json::string(self.key())
}

///|
/// 画面に出す日本語のラベル。
pub fn Kind::label(self : Kind) -> String {
  match self {
    Question => "質問"
    Request => "リクエスト"
    Feedback => "感想"
    Correction => "指摘"
    Greeting => "挨拶"
    FirstTime => "初見"
    Trouble => "トラブル"
    Abuse => "荒らし"
    Chatter => "雑談"
    Reaction => "反応"
    Unjudged => "未判定"
  }
}
