///|
/// CLI フラグで選んだ Source / Sink と各種設定。
pub(all) struct CliOptions {
  sources : Array[String]
  sinks : Array[String]
  port : Int
  host : String
  /// Jev に渡す配信の文脈
  context : String
  twitch_channels : Array[String]
  youtube_video_id : String?
  replay_path : String?
  /// replay の再生速度
  speed : Double
  /// stdin Source の参加者 ID に付けるプレフィックス（外部ブリッジ用）
  stdin_source : String
  /// 静的ファイルの場所。無ければバイナリに埋め込んだものを使う
  web_dir : String?
  /// 並行して Jev に投げる本数
  workers : Int
  queue_limit : Int
  /// 束ねる時間窓（秒）
  window_sec : Int
  threshold : Double
  metric : @lib.BundleMetric
  reaction_words : Array[String]
  /// この priority 以上なら種類によらず拾う
  priority_threshold : Double
  /// 拾うべき種類に求める priority の下限
  pickup_floor : Double
  /// 正解データ（拾った・スルー・期限切れ）の追記先。空なら書かない
  labels_path : String
  /// 話題になったら出す商品・URL の一覧（JSON）
  promos_path : String?
  /// 設定ファイルの場所
  config_path : String
} derive(Debug)

///|
pub suberror CliError {
  MissingValue(String)
  UnknownOption(String)
  BadNumber(String)
  /// 選べない値（フラグ, 値）
  BadValue(String, String)
  Help
  Version
} derive(Debug)

///|
pub suberror ConfigError {
  /// 型が違うキー
  Invalid(String)
} derive(Debug, Eq)

///|
pub const DEFAULT_CONFIG_PATH : String = "yuru-come.json"

///|
/// 何も指定しないときの設定。
pub fn CliOptions::default() -> CliOptions {
  {
    sources: ["stdin"],
    sinks: ["web"],
    port: DEFAULT_PORT,
    host: "127.0.0.1",
    context: "",
    twitch_channels: [],
    youtube_video_id: None,
    replay_path: None,
    speed: 1.0,
    stdin_source: "stdin",
    web_dir: None,
    workers: 2,
    queue_limit: 50,
    window_sec: 30,
    threshold: 0.85,
    metric: NormalizedLevenshtein,
    reaction_words: [],
    priority_threshold: 1.5,
    pickup_floor: 0.6,
    labels_path: "labels.jsonl",
    promos_path: None,
    config_path: DEFAULT_CONFIG_PATH,
  }
}

///|
/// 設定ファイル（`yuru-come.json`）を読む。キーは CLI のフラグ名と同じ（`--twitch` は `"twitch": [...]`）。
/// 無いキーは既定のまま。
pub fn CliOptions::from_json(json : Json) -> CliOptions raise ConfigError {
  guard json is Object(fields) else { raise Invalid("config") }
  let base = CliOptions::default()
  let strings = (key : String, current : Array[String]) => {
    match fields.get(key) {
      None => current
      Some(Array(items)) => {
        let out : Array[String] = []
        for item in items {
          guard item is String(s) else { raise Invalid(key) }
          out.push(s)
        }
        out
      }
      Some(_) => raise Invalid(key)
    }
  }
  let string = (key : String, current : String) => {
    match fields.get(key) {
      None => current
      Some(String(s)) => s
      Some(_) => raise Invalid(key)
    }
  }
  let optional = (key : String, current : String?) => {
    match fields.get(key) {
      None => current
      Some(String(s)) => Some(s)
      Some(Null) => None
      Some(_) => raise Invalid(key)
    }
  }
  let int = (key : String, current : Int) => {
    match fields.get(key) {
      None => current
      Some(Number(n, ..)) => n.to_int()
      Some(_) => raise Invalid(key)
    }
  }
  let double = (key : String, current : Double) => {
    match fields.get(key) {
      None => current
      Some(Number(n, ..)) => n
      Some(_) => raise Invalid(key)
    }
  }
  let metric = match fields.get("metric") {
    None => base.metric
    Some(String("levenshtein")) => NormalizedLevenshtein
    Some(String("jaro-winkler")) => JaroWinkler
    Some(_) => raise Invalid("metric")
  }
  {
    sources: strings("sources", base.sources),
    sinks: strings("sinks", base.sinks),
    port: int("port", base.port),
    host: string("host", base.host),
    context: string("context", base.context),
    twitch_channels: strings("twitch", base.twitch_channels).map(c => {
      c.trim_start(chars="#").to_owned()
    }),
    youtube_video_id: optional("youtube", base.youtube_video_id),
    replay_path: optional("replay", base.replay_path),
    speed: double("speed", base.speed),
    stdin_source: string("stdin_source", base.stdin_source),
    web_dir: optional("web_dir", base.web_dir),
    workers: int("workers", base.workers),
    queue_limit: int("queue_limit", base.queue_limit),
    window_sec: int("window", base.window_sec),
    threshold: double("threshold", base.threshold),
    metric,
    reaction_words: strings("reaction_words", base.reaction_words),
    priority_threshold: double("priority_threshold", base.priority_threshold),
    pickup_floor: double("pickup_floor", base.pickup_floor),
    labels_path: string("labels", base.labels_path),
    promos_path: optional("promos", base.promos_path),
    config_path: base.config_path,
  }
}

///|
pub const DEFAULT_PORT : Int = 8791

///|
pub let usage : String =
  #|使い方: yuru-come [--source <name>]... [--sink <name>]... [オプション]
  #|
  #|  --source stdin|twitch|youtube|replay  コメントの入口（複数指定可、既定 stdin）
  #|  --sink web|terminal                   出口（複数指定可、既定 web）
  #|  --twitch <channel>                    Twitch のチャンネル名（--source twitch 用、複数指定可）
  #|  --youtube <videoId>                   YouTube Live の動画 ID（--source youtube 用。YOUTUBE_API_KEY があれば Data API、無ければキー無しで読む）
  #|  --replay <file.tsv>                   再生するログ（--source replay 用。時刻ms<TAB>参加者ID<TAB>発言）
  #|  --speed <n>                           replay の再生速度（既定 1）
  #|  --stdin-source <name>                 stdin の参加者 ID に付ける名前（既定 stdin。TikTok ブリッジなら tiktok）
  #|  --context <text>                      Jev に渡す配信の文脈（配信タイトルや話題）
  #|  --port <n>                            ダッシュボードのポート（既定 8791）
  #|  --host <addr>                         ダッシュボードの待ち受けアドレス（既定 127.0.0.1）
  #|  --web-dir <dir>                       静的ファイルの場所（既定はバイナリに埋め込んだもの。web/ を編集しながら試すとき用）
  #|  --workers <n>                         並行して Jev に投げる本数（既定 2）
  #|  --queue-limit <n>                     Jev 待ちキューの上限（既定 50）
  #|  --window <sec>                        反応を束ねる時間窓（既定 30）
  #|  --threshold <0..1>                    短いコメントを同一視する類似度の下限（既定 0.85）
  #|  --metric levenshtein|jaro-winkler     類似度の種類（既定 levenshtein）
  #|  --reaction-word <word>                早期判定の辞書に足す語（複数指定可）
  #|  --priority-threshold <0..2>           この priority 以上なら種類によらず拾う（既定 1.5。2 より大きくすると種類だけで拾う）
  #|  --pickup-floor <0..2>                 トラブル・質問・リクエスト・指摘・初見を拾うのに求める priority の下限（既定 0.6。0 で種類だけで拾う）
  #|  --labels <file.jsonl>                 気になるコメントを配信者がどうしたか（拾った/スルー/期限切れ）の記録先（既定 labels.jsonl。空文字で書かない）
  #|  --config <file.json>                  設定ファイル（既定 yuru-come.json。キーはフラグ名と同じ。CLI が上書き）
  #|  --version                             バージョンを表示
  #|  --promos <file.json>                  話題になったらオーバーレイに QR とリンクを出す商品の一覧（[{label, url, keywords}]）
  #|
  #|環境変数: JEV_URL（既定 http://127.0.0.1:8000）、JEV_API_KEY（既定 local）、JEV_MODEL（既定 jev-latest）、YOUTUBE_API_KEY（任意）
  #|          OPENAI_API_KEY（任意。あれば 30 秒ごとに「いまの空気」を一文にする）、OPENAI_MODEL（既定 gpt-5.6-luna）

///|
/// 引数列（プログラム名を除く）を解釈する。`defaults` は設定ファイルの値（無ければ既定）。
/// 複数指定できる項目（--source / --sink / --twitch / --reaction-word）は、CLI で 1 つでも指定したら設定ファイルの分は使わない。
pub fn parse_cli(
  args : ArrayView[String],
  defaults? : CliOptions = CliOptions::default(),
) -> CliOptions raise CliError {
  let sources : Array[String] = []
  let sinks : Array[String] = []
  let reaction_words : Array[String] = []
  let twitch_channels : Array[String] = []
  let mut port = defaults.port
  let mut host = defaults.host
  let mut context = defaults.context
  let mut youtube_video_id = defaults.youtube_video_id
  let mut replay_path = defaults.replay_path
  let mut speed = defaults.speed
  let mut stdin_source = defaults.stdin_source
  let mut web_dir = defaults.web_dir
  let mut workers = defaults.workers
  let mut queue_limit = defaults.queue_limit
  let mut window_sec = defaults.window_sec
  let mut threshold = defaults.threshold
  let mut metric = defaults.metric
  let mut priority_threshold = defaults.priority_threshold
  let mut pickup_floor = defaults.pickup_floor
  let mut labels_path = defaults.labels_path
  let mut promos_path = defaults.promos_path
  let mut config_path = defaults.config_path
  let mut i = 0
  while i < args.length() {
    let flag = args[i]
    let value = () => {
      if i + 1 >= args.length() {
        raise MissingValue(flag)
      }
      i += 1
      args[i]
    }
    let int_value = () => {
      let text = value()
      @string.parse_int(text) catch {
        _ => raise BadNumber(text)
      }
    }
    // 1 以上でなければならない整数
    let positive_value = () => {
      let text = value()
      let n = @string.parse_int(text) catch { _ => raise BadNumber(text) }
      if n < 1 {
        raise BadValue(flag, text)
      }
      n
    }
    let double_value = () => {
      let text = value()
      @string.parse_double(text) catch {
        _ => raise BadNumber(text)
      }
    }
    match flag {
      "--help" | "-h" => raise Help
      "--version" | "-V" => raise Version
      "--config" => config_path = value()
      "--source" => sources.push(value())
      "--sink" => sinks.push(value())
      "--port" => port = int_value()
      "--host" => host = value()
      "--context" => context = value()
      "--twitch" =>
        twitch_channels.push(value().trim_start(chars="#").to_owned())
      "--youtube" => youtube_video_id = Some(value())
      "--replay" => replay_path = Some(value())
      "--speed" => {
        let text = value()
        speed = @string.parse_double(text) catch { _ => raise BadNumber(text) }
        if speed <= 0.0 {
          raise BadValue(flag, text)
        }
      }
      "--stdin-source" => stdin_source = value()
      "--web-dir" => web_dir = Some(value())
      "--workers" => workers = positive_value()
      "--queue-limit" => {
        let text = value()
        queue_limit = @string.parse_int(text) catch {
          _ => raise BadNumber(text)
        }
        if queue_limit < 0 {
          raise BadValue(flag, text)
        }
      }
      "--window" => window_sec = positive_value()
      "--threshold" => threshold = double_value()
      "--metric" =>
        metric = match value() {
          "levenshtein" => NormalizedLevenshtein
          "jaro-winkler" => JaroWinkler
          other => raise BadValue(flag, other)
        }
      "--reaction-word" => reaction_words.push(value())
      "--priority-threshold" => priority_threshold = double_value()
      "--pickup-floor" => pickup_floor = double_value()
      "--labels" => labels_path = value()
      "--promos" => promos_path = Some(value())
      _ => raise UnknownOption(flag)
    }
    i += 1
  }
  {
    sources: if sources.is_empty() {
      defaults.sources
    } else {
      sources
    },
    sinks: if sinks.is_empty() {
      defaults.sinks
    } else {
      sinks
    },
    port,
    host,
    context,
    twitch_channels: if twitch_channels.is_empty() {
      defaults.twitch_channels
    } else {
      twitch_channels
    },
    youtube_video_id,
    replay_path,
    speed,
    stdin_source,
    web_dir,
    workers,
    queue_limit,
    window_sec,
    threshold,
    metric,
    reaction_words: if reaction_words.is_empty() {
      defaults.reaction_words
    } else {
      reaction_words
    },
    priority_threshold,
    pickup_floor,
    labels_path,
    promos_path,
    config_path,
  }
}
