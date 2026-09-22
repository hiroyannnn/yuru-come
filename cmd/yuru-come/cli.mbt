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
  web_dir : String
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
} derive(Debug)

///|
pub suberror CliError {
  MissingValue(String)
  UnknownOption(String)
  BadNumber(String)
  /// 選べない値（フラグ, 値）
  BadValue(String, String)
  Help
} derive(Debug)

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
  #|  --web-dir <dir>                       静的ファイルの場所（既定 web）
  #|  --workers <n>                         並行して Jev に投げる本数（既定 2）
  #|  --queue-limit <n>                     Jev 待ちキューの上限（既定 50）
  #|  --window <sec>                        反応を束ねる時間窓（既定 30）
  #|  --threshold <0..1>                    短いコメントを同一視する類似度の下限（既定 0.85）
  #|  --metric levenshtein|jaro-winkler     類似度の種類（既定 levenshtein）
  #|  --reaction-word <word>                早期判定の辞書に足す語（複数指定可）
  #|  --priority-threshold <0..2>           この priority 以上なら種類によらず拾う（既定 1.5。2 より大きくすると種類だけで拾う）
  #|  --pickup-floor <0..2>                 トラブル・質問・リクエスト・指摘・初見を拾うのに求める priority の下限（既定 0.6。0 で種類だけで拾う）
  #|
  #|環境変数: JEV_URL（既定 http://127.0.0.1:8000）、JEV_API_KEY（既定 local）、JEV_MODEL（既定 jev-latest）、YOUTUBE_API_KEY（任意）
  #|          OPENAI_API_KEY（任意。あれば 30 秒ごとに「いまの空気」を一文にする）、OPENAI_MODEL（既定 gpt-5-mini）

///|
/// 引数列（プログラム名を除く）を解釈する。
pub fn parse_cli(args : ArrayView[String]) -> CliOptions raise CliError {
  let sources : Array[String] = []
  let sinks : Array[String] = []
  let reaction_words : Array[String] = []
  let mut port = DEFAULT_PORT
  let mut host = "127.0.0.1"
  let mut context = ""
  let twitch_channels : Array[String] = []
  let mut youtube_video_id : String? = None
  let mut replay_path : String? = None
  let mut speed = 1.0
  let mut stdin_source = "stdin"
  let mut web_dir = "web"
  let mut workers = 2
  let mut queue_limit = 50
  let mut window_sec = 30
  let mut threshold = 0.85
  let mut metric : @lib.BundleMetric = NormalizedLevenshtein
  let mut priority_threshold = 1.5
  let mut pickup_floor = 0.6
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
      "--web-dir" => web_dir = value()
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
      _ => raise UnknownOption(flag)
    }
    i += 1
  }
  {
    sources: if sources.is_empty() {
      ["stdin"]
    } else {
      sources
    },
    sinks: if sinks.is_empty() {
      ["web"]
    } else {
      sinks
    },
    port,
    host,
    context,
    twitch_channels,
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
    reaction_words,
    priority_threshold,
    pickup_floor,
  }
}
