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
/// Jev の criteria に渡す説明。その種類のコメントによくある言い回しを具体的に書く。
/// Reaction / Unjudged は Jev に聞かないので空。
pub fn Kind::description(self : Kind) -> String {
  match self {
    Question =>
      "配信者への質問。配信者に答えてほしいこと。「これ何のゲームですか？」「今日は何時までやりますか？」「その設定どうやってるんですか？」「〜って知ってますか？」"
    Request =>
      "配信者へのリクエスト・提案・指示。「次は〜をやってほしい」「〜してみて」「右の部屋を先に見たほうがいいよ」「BGM 変えてほしい」「セーブしといたほうがいい」"
    Feedback =>
      "配信や配信者への感想・応援・称賛。「今日の配信おもしろい」「その発想はなかった、うまいなあ」「がんばれ、応援してます」「声が落ち着く」"
    Correction =>
      "配信者のミスや見落としの指摘、ツッコミ。「それ逆じゃない？」「さっきの宝箱取り忘れてるよ」「つなぐ先が間違ってる」「字が違う、〜が正しい」「いや今言ったことと違うｗ」"
    Greeting =>
      "来たとき・帰るときの挨拶。「こんにちは」「こんばんは、今日も来ました」「おはようございます」「わこつ」「仕事終わって来ました」「そろそろ落ちます、おやすみなさい」"
    FirstTime =>
      "初めて見に来たこと・初めてコメントすることを名乗る挨拶。「初見です」「初見です、よろしくお願いします」「初コメです」「はじめまして、おすすめから来ました」「切り抜きから来ました」"
    Trouble =>
      "配信そのものの技術的なトラブルの報告。「音が出ていない」「マイクの音が聞こえない」「画面が止まってる」「映像がカクカクする」「ゲーム音が大きすぎて声が聞こえない」「画面が真っ暗」「配信が落ちた？」"
    Abuse =>
      "荒らし・誹謗中傷・スパム・宣伝。「下手くそ、やめちまえ」「つまんね、消えろ」「きもい」、配信と関係ない URL や宣伝の連投、他の配信者や視聴者への悪口"
    Chatter =>
      "配信者に向けていない、視聴者同士の雑談や独り言。「さっきのコメントの人に同意」「明日仕事だるい」「ごはん食べてくる」「〜さんこんばんは」「自分はこのゲーム積んでる」"
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
