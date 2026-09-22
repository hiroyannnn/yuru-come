///|
fn parse(args : Array[String]) -> CliOptions raise CliError {
  parse_cli(args[:])
}

///|
test "引数なしなら stdin から読んでウェブダッシュボードに出す" {
  let options = parse([])
  assert_eq(options.sources, ["stdin"])
  assert_eq(options.sinks, ["web"])
  assert_eq(options.port, 8791)
  assert_eq(options.host, "127.0.0.1")
  assert_eq(options.context, "")
  assert_eq(options.workers, 2)
  assert_eq(options.queue_limit, 50)
  assert_eq(options.window_sec, 30)
  assert_eq(options.threshold, 0.85)
  assert_eq(options.metric, NormalizedLevenshtein)
  assert_eq(options.priority_threshold, 1.5)
}

///|
test "拾い上げの priority の閾値を変えられる（score が当てにならない判定サーバ向け）" {
  assert_eq(parse(["--priority-threshold", "2.1"]).priority_threshold, 2.1)
}

///|
test "拾うべき種類に求める priority の下限を変えられる" {
  assert_eq(parse([]).pickup_floor, 0.6)
  assert_eq(parse(["--pickup-floor", "1.0"]).pickup_floor, 1.0)
}

///|
test "README の起動例を解釈できる" {
  let options = parse([
    "--source", "twitch", "--twitch", "somechannel", "--port", "8791", "--context",
    "Factorio 配信",
  ])
  assert_eq(options.sources, ["twitch"])
  assert_eq(options.twitch_channels, ["somechannel"])
  assert_eq(options.context, "Factorio 配信")
}

///|
test "--twitch は複数指定でき、# は取り除く" {
  let options = parse([
    "--source", "twitch", "--twitch", "#alice", "--twitch", "bob",
  ])
  assert_eq(options.twitch_channels, ["alice", "bob"])
}

///|
test "--source と --sink と --reaction-word は複数指定できる" {
  let options = parse([
    "--source", "twitch", "--source", "youtube", "--sink", "web", "--sink", "terminal",
    "--twitch", "ch", "--youtube", "VIDEO", "--reaction-word", "てぇてぇ", "--reaction-word",
    "ぽまえら",
  ])
  assert_eq(options.sources, ["twitch", "youtube"])
  assert_eq(options.sinks, ["web", "terminal"])
  assert_eq(options.youtube_video_id, Some("VIDEO"))
  assert_eq(options.reaction_words, ["てぇてぇ", "ぽまえら"])
}

///|
test "replay はログのパスと倍速を取る" {
  let options = parse([
    "--source", "replay", "--replay", "samples/wave.tsv", "--speed", "10",
  ])
  assert_eq(options.replay_path, Some("samples/wave.tsv"))
  assert_eq(options.speed, 10.0)
}

///|
test "束ねと流量制御の設定を変えられる" {
  let options = parse([
    "--window", "60", "--threshold", "0.9", "--metric", "jaro-winkler", "--queue-limit",
    "20", "--workers", "4",
  ])
  assert_eq(options.window_sec, 60)
  assert_eq(options.threshold, 0.9)
  assert_eq(options.metric, JaroWinkler)
  assert_eq(options.queue_limit, 20)
  assert_eq(options.workers, 4)
}

///|
fn parse_error(args : Array[String]) -> CliError? {
  try parse(args) catch {
    err => Some(err)
  } noraise {
    _ => None
  }
}

///|
test "値の無いフラグ、知らないフラグ、数値でない値はエラー" {
  assert_true(parse_error(["--port"]) is Some(MissingValue("--port")))
  assert_true(parse_error(["--nope"]) is Some(UnknownOption("--nope")))
  assert_true(parse_error(["--port", "abc"]) is Some(BadNumber("abc")))
  assert_true(parse_error(["--speed", "fast"]) is Some(BadNumber("fast")))
  assert_true(
    parse_error(["--metric", "cosine"]) is Some(BadValue("--metric", "cosine")),
  )
}

///|
test "--help は Help を返す" {
  assert_true(parse_error(["--help"]) is Some(Help))
}

///|
test "本数や上限に使えない値はエラー" {
  assert_true(
    parse_error(["--workers", "0"]) is Some(BadValue("--workers", "0")),
  )
  assert_true(
    parse_error(["--queue-limit", "-1"])
    is Some(BadValue("--queue-limit", "-1")),
  )
  assert_true(parse_error(["--window", "0"]) is Some(BadValue("--window", "0")))
  assert_true(parse_error(["--speed", "0"]) is Some(BadValue("--speed", "0")))
}

///|
test "正解データの書き先は変えられ、空にすると書かない" {
  assert_eq(parse([]).labels_path, "labels.jsonl")
  assert_eq(parse(["--labels", "out/l.jsonl"]).labels_path, "out/l.jsonl")
  assert_eq(parse(["--labels", ""]).labels_path, "")
}
