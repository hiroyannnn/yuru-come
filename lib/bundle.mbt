///|
/// 短いコメントを同一視するときに使う類似度。
pub(all) enum BundleMetric {
  /// 正規化 Levenshtein。短い文字列では 1 文字違いでも大きく下がるので束ねすぎない（既定）
  NormalizedLevenshtein
  /// Jaro-Winkler。出だしが同じ文字列に甘い。反応の言い回しのゆれを広く拾いたいとき
  JaroWinkler
} derive(Debug, Eq)

///|
pub(all) struct BundleConfig {
  /// 束ねる時間窓（ミリ秒）
  window_ms : Int64
  /// 同一視する類似度の下限
  threshold : Double
  /// 類似度で同一視するのは、正規化後の文字数がこれ以下のコメントだけ
  fuzzy_max_len : Int
  metric : BundleMetric
} derive(Debug)

///|
pub fn BundleConfig::new(
  window_ms? : Int64 = 30000,
  threshold? : Double = 0.85,
  fuzzy_max_len? : Int = 12,
  metric? : BundleMetric = NormalizedLevenshtein,
) -> BundleConfig {
  { window_ms, threshold, fuzzy_max_len, metric, }
}

///|
/// コメント 1 件を束に入れた結果。
pub(all) struct BundleHit {
  /// 入った束のキー（類似度で束ねられた場合は、先にあった束のキー）
  key : String
  /// このコメントを含めた、時間窓の中の件数
  count : Int
  /// キーの完全一致（または新しい束）なら true、類似度で入ったなら false
  exact : Bool
} derive(Debug, Eq)

///|
/// 画面に出す束の要約。
pub(all) struct BundleSummary {
  key : String
  /// 代表テキスト（束の中でいちばん短い原文）
  representative : String
  count : Int
  /// 時間窓の中でこの反応をした参加者の数
  participants : Int
  last_at : Int64
} derive(Debug, Eq, ToJson)

///|
struct BundleEntry {
  at : Int64
  participant_id : String
}

///|
struct Bundle {
  key : String
  key_len : Int
  mut representative : String
  /// 古い順
  mut entries : Array[BundleEntry]
}

///|
/// 同じ反応を時間窓の中でまとめるカウンタ。
pub struct Bundler {
  config : BundleConfig
  mut bundles : Array[Bundle]
}

///|
pub fn Bundler::new(config? : BundleConfig = BundleConfig::new()) -> Bundler {
  { config, bundles: [], }
}

///|
/// 時間窓を過ぎた分を捨てる。空になった束は消える。
pub fn Bundler::prune(self : Bundler, now : Int64) -> Unit {
  let oldest = now - self.config.window_ms
  for bundle in self.bundles {
    if bundle.entries.length() > 0 && bundle.entries[0].at < oldest {
      bundle.entries = bundle.entries.filter(entry => entry.at >= oldest)
    }
  }
  self.bundles = self.bundles.filter(bundle => !bundle.entries.is_empty())
}

///|
fn Bundler::similarity(self : Bundler, a : String, b : String) -> Double {
  match self.config.metric {
    NormalizedLevenshtein => @strsim.normalized_levenshtein(a, b)
    JaroWinkler => @strsim.jaro_winkler(a, b)
  }
}

///|
/// キーが完全一致する束、なければ短いコメントに限って類似度がいちばん高い束を探す。
fn Bundler::find(self : Bundler, key : String, key_len : Int) -> Bundle? {
  for bundle in self.bundles {
    if bundle.key == key {
      return Some(bundle)
    }
  }
  let max_len = self.config.fuzzy_max_len
  guard key_len <= max_len else { return None }
  let mut best : Bundle? = None
  let mut best_score = self.config.threshold
  for bundle in self.bundles {
    guard bundle.key_len <= max_len else { continue }
    let score = self.similarity(bundle.key, key)
    if score >= best_score {
      // 同点なら先にあった束を優先する
      if best is None || score > best_score {
        best = Some(bundle)
      }
      best_score = score
    }
  }
  best
}

///|
/// 正規化済みのキーでコメントを束に入れる。
pub fn Bundler::add(
  self : Bundler,
  key : String,
  comment : Comment,
  now : Int64,
) -> BundleHit {
  self.prune(now)
  let text = comment.text.trim(chars=" \t\r\n　").to_owned()
  let bundle = match self.find(key, key.char_length()) {
    Some(bundle) => bundle
    None => {
      let bundle : Bundle = {
        key,
        key_len: key.char_length(),
        representative: text,
        entries: [],
      }
      self.bundles.push(bundle)
      bundle
    }
  }
  if text.char_length() < bundle.representative.char_length() {
    bundle.representative = text
  }
  bundle.entries.push({ at: now, participant_id: comment.participant_id, })
  { key: bundle.key, count: bundle.entries.length(), exact: bundle.key == key, }
}

///|
/// 件数の多い順（同数なら新しい順）の束の一覧。
pub fn Bundler::summaries(
  self : Bundler,
  now : Int64,
  min_count? : Int = 2,
  limit? : Int = 5,
) -> Array[BundleSummary] {
  self.prune(now)
  let summaries : Array[BundleSummary] = []
  for bundle in self.bundles {
    guard bundle.entries.length() >= min_count else { continue }
    let participants : Map[String, Unit] = Map([])
    let mut last_at : Int64 = 0
    for entry in bundle.entries {
      participants[entry.participant_id] = ()
      if entry.at > last_at {
        last_at = entry.at
      }
    }
    summaries.push({
      key: bundle.key,
      representative: bundle.representative,
      count: bundle.entries.length(),
      participants: participants.length(),
      last_at,
    })
  }
  summaries.sort_by((a, b) => {
    if a.count != b.count {
      b.count.compare(a.count)
    } else {
      b.last_at.compare(a.last_at)
    }
  })
  if summaries.length() > limit {
    summaries[:limit].to_owned()
  } else {
    summaries
  }
}
