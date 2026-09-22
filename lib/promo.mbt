///|
/// 話題になったら画面に出す商品・URL。`promos.json` の 1 項目。
pub(all) struct Promo {
  label : String
  url : String
  /// このどれかを含むコメントが来たら出す（正規化して照合する）
  keywords : Array[String]
} derive(Debug, Eq, ToJson)

///|
pub(all) suberror PromoError {
  /// 欠けている・型が違うフィールド名
  Invalid(String)
} derive(Debug, Eq)

///|
/// `[{"label": …, "url": …, "keywords": […]}, …]` を読む。
pub fn parse_promos(json : Json) -> Array[Promo] raise PromoError {
  guard json is Array(items) else { raise Invalid("promos") }
  let promos : Array[Promo] = []
  for item in items {
    guard item is Object(fields) else { raise Invalid("promos") }
    let label = match fields.get("label") {
      Some(String(s)) if !s.is_empty() => s
      _ => raise Invalid("label")
    }
    let url = match fields.get("url") {
      Some(String(s)) if !s.is_empty() => s
      _ => raise Invalid("url")
    }
    let keywords : Array[String] = []
    match fields.get("keywords") {
      Some(Array(words)) if !words.is_empty() =>
        for word in words {
          match word {
            String(w) if !w.is_empty() => keywords.push(w)
            _ => raise Invalid("keywords")
          }
        }
      _ => raise Invalid("keywords")
    }
    promos.push({ label, url, keywords, })
  }
  promos
}

///|
pub(all) struct PromoConfig {
  /// 出してから消すまで（ミリ秒）
  show_ms : Int64
  /// 同じ商品を出し直さない時間（ミリ秒）
  cooldown_ms : Int64
} derive(Debug)

///|
pub fn PromoConfig::new(
  show_ms? : Int64 = 60_000,
  cooldown_ms? : Int64 = 300_000,
) -> PromoConfig {
  { show_ms, cooldown_ms, }
}

///|
/// 表示中の商品。
pub(all) struct PromoView {
  label : String
  url : String
  /// きっかけになったコメント
  trigger : String
  shown_at : Int64
} derive(Debug, Eq, ToJson)

///|
struct PromoEntry {
  promo : Promo
  /// 正規化済みのキーワード
  keys : Array[String]
  mut last_shown : (String, Int64)?
}

///|
/// 商品の話題を拾って、表示中のものを管理する。
pub struct PromoBoard {
  config : PromoConfig
  entries : Array[PromoEntry]
}

///|
pub fn PromoBoard::new(
  promos : Array[Promo],
  config? : PromoConfig = PromoConfig::new(),
) -> PromoBoard {
  {
    config,
    entries: promos.map(promo => {
      promo,
      keys: promo.keywords.map(word => normalize(word)),
      last_shown: None,
    }),
  }
}

///|
/// コメント（原文）が商品のキーワードに当たれば出す。当たった商品を返す。
/// クールダウン中の商品は出し直さない。
pub fn PromoBoard::notice(
  self : PromoBoard,
  text : String,
  now : Int64,
) -> Promo? {
  let key = normalize(text)
  for entry in self.entries {
    guard entry.keys.iter().any(k => key.contains(k)) else { continue }
    if entry.last_shown is Some((_, at)) && now - at < self.config.cooldown_ms {
      continue
    }
    entry.last_shown = Some((text, now))
    return Some(entry.promo)
  }
  None
}

///|
/// 表示中の商品（出した順）。
pub fn PromoBoard::active(self : PromoBoard, now : Int64) -> Array[PromoView] {
  let views : Array[PromoView] = []
  for entry in self.entries {
    guard entry.last_shown is Some((trigger, shown_at)) &&
      now - shown_at < self.config.show_ms else {
      continue
    }
    views.push({
      label: entry.promo.label,
      url: entry.promo.url,
      trigger,
      shown_at,
    })
  }
  views.sort_by((a, b) => a.shown_at.compare(b.shown_at))
  views
}
