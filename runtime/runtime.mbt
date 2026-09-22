///|
/// 全 Source を同時に走らせ、コメントをエンジンに取り込みながら、判定待ちを `workers` 本で並行して判定する。
///
/// - `judge` は差し替え可能な判定関数（配信の文脈とコメントを受け取る。HTTP 実装は `jev` パッケージ）
/// - `submit` は判定を待たずにすぐ戻る。判定が遅くてもチャットの読み取りは止まらず、
///   あふれた分はエンジンが未判定のまま流す
/// - 判定の失敗とタイムアウトは未判定として数え、次のコメントに進む
/// - 全 Source の `run` が戻り、判定待ちが無くなったら `run` も戻る
pub async fn run(
  engine : @lib.Engine,
  judge : async (String, @lib.Comment) -> @lib.Triage,
  sources : Array[&@lib.Source],
  workers? : Int = 2,
  judge_timeout_ms? : Int = 10_000,
) -> Unit {
  let wake = @cond_var.Cond()
  let sources_done = Ref(false)
  let submit : async (@lib.Comment) -> Unit = comment => {
    let now = @async.now()
    engine.ingest({ ..comment, at: now, }, now)
    wake.signal()
  }
  @async.with_task_group(group => {
    for _ in 0..<workers {
      group.spawn_bg(() => {
        while true {
          guard engine.take_next() is Some(pending) else {
            if sources_done.val {
              break
            }
            wake.wait()
            continue
          }
          let triage = try
            @async.with_timeout(judge_timeout_ms, () => {
              judge(engine.context(), pending.comment)
            })
          catch {
            err => {
              if @async.is_being_cancelled() {
                raise err
              }
              log("判定に失敗: \{err}")
              None
            }
          } noraise {
            triage => Some(triage)
          }
          engine.complete(pending, triage, @async.now())
        }
      })
    }
    @async.with_task_group(source_group => {
      for source in sources {
        source_group.spawn_bg(allow_failure=true, () => source.run(submit))
      }
    })
    sources_done.val = true
    wake.broadcast()
  })
}

///|
/// 標準エラー出力に 1 行書く（標準出力はターミナル Sink が使うので分ける）。
pub async fn log(message : String) -> Unit {
  @stdio.stderr.write("[yuru-come] \{message}\n")
}

///|
/// 「いまの空気」の一文を LLM に書かせるループ。`interval_ms` ごとに、前回から新しいコメントが来ていれば呼ぶ。
/// 失敗はログに出して次の周期に進む（画面はテンプレートの一文に戻る）。戻らない。
pub async fn summarize_loop(
  engine : @lib.Engine,
  summarize : async (String, String) -> String,
  interval_ms? : Int = 30_000,
) -> Unit {
  let mut last_entry_id = 0
  while true {
    @async.sleep(interval_ms)
    let now = @async.now()
    let state = engine.state(now)
    guard @lib.summary_needed(state, last_entry_id~) else { continue }
    last_entry_id = state.flow[0].id
    let prompt = @lib.summary_prompt(state)
    let text = summarize(prompt.system, prompt.user) catch {
      err => {
        if @async.is_being_cancelled() {
          raise err
        }
        log("要約に失敗: \{err}")
        continue
      }
    }
    let cleaned = @lib.clean_summary(text)
    if !cleaned.is_empty() {
      engine.set_summary(cleaned, @async.now())
      log("空気: \{cleaned}")
    }
  }
}
