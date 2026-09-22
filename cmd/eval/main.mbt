///|
let usage : String =
  #|使い方: moon run --target native cmd/eval -- [--data eval/comments.tsv] [--context <text>] [--priority-threshold 1.5] [--pickup-floor 0.6]
  #|
  #|評価セットを 1 件ずつ仕分けて、kind の正解率と混同行列、「拾うべき」の適合率と再現率、所要時間を出す。
  #|本番と同じく、早期判定で reaction と決まったコメントは Jev に投げない。
  #|環境変数: JEV_URL（既定 http://127.0.0.1:8000）、JEV_API_KEY（既定 local）、JEV_MODEL（既定 jev-latest）

///|
const DEFAULT_CONTEXT : String = "ゲーム実況の配信。雑談もまじえながらアクション RPG を進めている"

///|
async fn main {
  @runtime.load_dotenv() |> ignore
  let args = @env.args()
  let mut data = "eval/comments.tsv"
  let mut context = DEFAULT_CONTEXT
  let mut threshold = 1.5
  let mut floor = 0.6
  let mut i = 1
  while i < args.length() {
    match (args[i], args.get(i + 1)) {
      ("--data", Some(value)) => data = value
      ("--context", Some(value)) => context = value
      ("--priority-threshold", Some(value)) =>
        threshold = @string.parse_double(value) catch {
          _ => {
            println("数値ではありません: \{value}\n\n\{usage}")
            return
          }
        }
      ("--pickup-floor", Some(value)) =>
        floor = @string.parse_double(value) catch {
          _ => {
            println("数値ではありません: \{value}\n\n\{usage}")
            return
          }
        }
      _ => {
        println(usage)
        return
      }
    }
    i += 2
  }
  run(data, context, threshold, floor) catch {
    err => println("エラー: \{err}")
  }
}

///|
async fn run(
  data : String,
  context : String,
  threshold : Double,
  floor : Double,
) -> Unit {
  let rows : Array[EvalRow] = []
  for line in @fs.read_file(data).text().split("\n") {
    if parse_eval_line(line.to_owned()) is Some(row) {
      rows.push(row)
    }
  }
  let client = @jev.JevClient::from_env()
  let rules = @lib.ReactionRules::new()
  let pickup_config = @lib.PickupConfig::new(
    priority_threshold=threshold,
    kind_floor=floor,
  )
  let kind_only = @lib.PickupConfig::new(
    priority_threshold=99.0,
    kind_floor=0.0,
  )
  let overall = Confusion::new()
  let jev_only = Confusion::new()
  let by_rule = PickupScore::new()
  let by_kind = PickupScore::new()
  let latencies : Array[Int] = []
  let misses : Array[String] = []
  // 正解の kind ごとの priority（Jev に投げた分だけ）
  let priorities : Map[String, Array[Double]] = Map([])
  let mut early = 0
  let mut failed = 0
  println("# yuru-come 仕分け評価")
  println("")
  println("- 判定サーバ: \{client.base_url}（model: \{client.model}）")
  println("- 評価セット: \{data}（\{rows.length()} 件）")
  println("- 文脈: \{context}")
  println("")
  for row in rows {
    let (kind, priority) = if rules.is_reaction(row.text) {
      early += 1
      (@lib.Kind::Reaction, 0.0)
    } else {
      let started = @async.now()
      let triage = client.judge(
        context,
        @lib.Comment::new("eval:row", row.text),
      ) catch {
        err => {
          failed += 1
          println("判定に失敗: \{row.text}: \{err}")
          continue
        }
      }
      latencies.push((@async.now() - started).to_int())
      jev_only.add(row.kind, triage.kind)
      match priorities.get(row.kind.key()) {
        Some(values) => values.push(triage.priority)
        None => priorities[row.kind.key()] = [triage.priority]
      }
      (triage.kind, triage.priority)
    }
    overall.add(row.kind, kind)
    by_rule.add(
      expected=row.pickup,
      predicted=pickup_config.should_pick_up(kind, priority),
    )
    by_kind.add(
      expected=row.pickup,
      predicted=kind_only.should_pick_up(kind, priority),
    )
    if kind != row.kind {
      misses.push(
        "- 正解 \{row.kind.key()} → 判定 \{kind.key()}（priority \{format_hundredths(priority)}）: \{row.text}",
      )
    }
  }
  let total_ms = latencies.fold(init=0, (sum, ms) => sum + ms)
  println("## kind")
  println("")
  println(
    "- 全体（早期判定 + Jev）: \{overall.correct()} / \{overall.total()} = \{percent(overall.accuracy())}",
  )
  println(
    "- Jev に投げた分だけ: \{jev_only.correct()} / \{jev_only.total()} = \{percent(jev_only.accuracy())}",
  )
  println(
    "- 早期判定で Jev を省いた: \{early} / \{rows.length()} 件、判定失敗: \{failed} 件",
  )
  println("")
  println(overall.render())
  println("")
  println("## 拾うべきか")
  println("")
  println("| ルール | 適合率 | 再現率 |")
  println("| --- | --- | --- |")
  println(
    "| 種類（priority ≥ \{floor}）または priority ≥ \{threshold} | \{percent(by_rule.precision())} | \{percent(by_rule.recall())} |",
  )
  println(
    "| 種類だけ | \{percent(by_kind.precision())} | \{percent(by_kind.recall())} |",
  )
  println("")
  println("## priority（正解の kind ごと、Jev に投げた分だけ）")
  println("")
  println("| 正解の kind | 件数 | 平均 | 最小 | 最大 |")
  println("| --- | --- | --- | --- | --- |")
  for kind in kind_order {
    guard priorities.get(kind.key()) is Some(values) else { continue }
    let sum = values.fold(init=0.0, (a, b) => a + b)
    let lowest = values.fold(init=values[0], (a, b) => if b < a { b } else { a })
    let highest = values.fold(init=values[0], (a, b) => {
      if b > a {
        b
      } else {
        a
      }
    })
    println(
      "| \{kind.key()} | \{values.length()} | \{format_hundredths(sum / values.length().to_double())} | \{format_hundredths(lowest)} | \{format_hundredths(highest)} |",
    )
  }
  println("")
  println(
    "## 所要時間（Jev 1 リクエスト = kind + priority の 2 質問）",
  )
  println("")
  println(
    "- 平均 \{if latencies.is_empty() { 0 } else { total_ms / latencies.length() }}ms / 中央値 \{percentile(latencies, 50)}ms / p95 \{percentile(latencies, 95)}ms（\{latencies.length()} リクエスト、合計 \{total_ms}ms）",
  )
  println("")
  println("## 外した判定")
  println("")
  for miss in misses {
    println(miss)
  }
}

///|
fn percent(value : Double) -> String {
  "\{format_tenths(value * 100.0)}%"
}

///|
fn format_tenths(value : Double) -> String {
  let tenths = (value * 10.0 + 0.5).floor().to_int()
  "\{tenths / 10}.\{tenths % 10}"
}

///|
fn format_hundredths(value : Double) -> String {
  let hundredths = (value * 100.0 + 0.5).floor().to_int()
  let frac = hundredths % 100
  "\{hundredths / 100}.\{if frac < 10 { "0" } else { "" }}\{frac}"
}
