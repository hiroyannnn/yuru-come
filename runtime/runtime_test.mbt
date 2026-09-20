///|
/// 決まったコメント列を順に submit するだけの Source。
struct ArraySource {
  comments : Array[String]
  /// 全部 submit し終わるまでにかかった時間（ミリ秒）
  elapsed : Ref[Int64]
}

///|
impl @lib.Source for ArraySource with fn run(self, submit) {
  let started = @async.now()
  for i, text in self.comments {
    submit(@lib.Comment::new("test:u\{i}", text, author="u\{i}"))
  }
  self.elapsed.val = @async.now() - started
}

///|
fn triage(kind : @lib.Kind, priority : Double) -> @lib.Triage {
  {
    kind,
    kind_probabilities: Map([]),
    kind_confidence: 0.9,
    priority,
    priority_confidence: 0.9,
  }
}

///|
suberror FakeJudgeError {
  Boom
} derive(Debug)

///|
/// 1 件あたり `delay_ms` かかる偽の判定関数。呼ばれた回数と同時実行数の最大を記録する。
struct SlowJudge {
  delay_ms : Int
  calls : Ref[Int]
  running : Ref[Int]
  max_running : Ref[Int]
  contexts : Array[String]
}

///|
fn SlowJudge::new(delay_ms : Int) -> SlowJudge {
  {
    delay_ms,
    calls: Ref(0),
    running: Ref(0),
    max_running: Ref(0),
    contexts: [],
  }
}

///|
async fn SlowJudge::judge(
  self : SlowJudge,
  context : String,
  comment : @lib.Comment,
) -> @lib.Triage {
  self.calls.val += 1
  self.contexts.push(context)
  self.running.val += 1
  if self.running.val > self.max_running.val {
    self.max_running.val = self.running.val
  }
  defer {
    self.running.val -= 1
  }
  @async.sleep(self.delay_ms)
  if comment.text.contains("判定失敗") {
    raise Boom
  }
  if comment.text.contains("？") {
    triage(Question, 1.2)
  } else {
    triage(Chatter, 0.1)
  }
}

///|
async test "Source のコメントを判定し、全部片付いたら戻る" {
  let engine = @lib.Engine::new(
    config=@lib.EngineConfig::new(context="雑談配信"),
  )
  let judge = SlowJudge::new(1)
  let source : ArraySource = {
    comments: [
      "草", "これ何のゲームですか？", "今日は仕事が大変だった",
      "wwww",
    ],
    elapsed: Ref(0),
  }
  @runtime.run(engine, (context, comment) => judge.judge(context, comment), [
    source,
  ])
  let state = engine.state(@async.now())
  assert_eq(state.stats.received, 4)
  assert_eq(state.stats.early, 2)
  assert_eq(state.stats.judged, 2)
  assert_eq(state.stats.queue_length, 0)
  assert_eq(state.stats.in_flight, 0)
  assert_eq(judge.calls.val, 2)
  assert_eq(judge.contexts, ["雑談配信", "雑談配信"])
  assert_eq(state.pickups.map(item => item.comment.text), [
    "これ何のゲームですか？",
  ])
}

///|
async test "判定が遅くても取り込みは待たされず、あふれた分は落とす" {
  let engine = @lib.Engine::new(config=@lib.EngineConfig::new(queue_limit=5))
  let judge = SlowJudge::new(30)
  let comments : Array[String] = []
  for i in 0..<40 {
    comments.push(
      "中身のあるコメントその\{i}番目、それぞれ別の話題について",
    )
  }
  let source : ArraySource = { comments, elapsed: Ref(0), }
  @runtime.run(
    engine,
    (context, comment) => judge.judge(context, comment),
    [source],
    workers=1,
  )
  let stats = engine.state(@async.now()).stats
  // 40 件を直列に判定すると 1200ms かかる。取り込みはそれを待たない
  assert_true(source.elapsed.val < 300, msg="elapsed=\{source.elapsed.val}")
  assert_eq(stats.received, 40)
  assert_true(stats.dropped >= 30, msg="dropped=\{stats.dropped}")
  assert_eq(stats.judged + stats.dropped, 40)
  assert_eq(stats.queue_length, 0)
}

///|
async test "workers の数だけ並行して判定する" {
  let engine = @lib.Engine::new()
  let judge = SlowJudge::new(20)
  let comments : Array[String] = []
  for i in 0..<9 {
    comments.push(
      "中身のあるコメントその\{i}番目、それぞれ別の話題について",
    )
  }
  @runtime.run(
    engine,
    (context, comment) => judge.judge(context, comment),
    [({ comments, elapsed: Ref(0), } : ArraySource)],
    workers=3,
  )
  assert_eq(judge.max_running.val, 3)
  assert_eq(engine.state(@async.now()).stats.judged, 9)
}

///|
async test "判定の失敗は未判定として数え、ほかのコメントの処理は続ける" {
  let engine = @lib.Engine::new()
  let judge = SlowJudge::new(1)
  let source : ArraySource = {
    comments: [
      "これは判定失敗するコメントです", "これ何のゲームですか？",
    ],
    elapsed: Ref(0),
  }
  @runtime.run(engine, (context, comment) => judge.judge(context, comment), [
    source,
  ])
  let stats = engine.state(@async.now()).stats
  assert_eq(stats.failed, 1)
  assert_eq(stats.judged, 1)
}

///|
async test "判定がタイムアウトしたら未判定にして次へ進む" {
  let engine = @lib.Engine::new()
  let judge = SlowJudge::new(200)
  let source : ArraySource = {
    comments: ["返事が遅すぎるコメントです、どうなるかな"],
    elapsed: Ref(0),
  }
  @runtime.run(
    engine,
    (context, comment) => judge.judge(context, comment),
    [source],
    judge_timeout_ms=20,
  )
  assert_eq(engine.state(@async.now()).stats.failed, 1)
}

///|
async test "複数の Source を同時に走らせる" {
  let engine = @lib.Engine::new()
  let judge = SlowJudge::new(1)
  let a : ArraySource = { comments: ["草", "草"], elapsed: Ref(0), }
  let b : ArraySource = { comments: ["8888"], elapsed: Ref(0), }
  @runtime.run(engine, (context, comment) => judge.judge(context, comment), [
    a, b,
  ])
  assert_eq(engine.state(@async.now()).stats.received, 3)
}
