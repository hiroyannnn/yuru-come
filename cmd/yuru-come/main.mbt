///|
async fn main {
  let options = parse_cli(@env.args()[1:]) catch {
    Help => {
      println(usage)
      return
    }
    err => {
      println("引数エラー: \{Repr(err)}\n\n\{usage}")
      return
    }
  }
  start(options) catch {
    err => println("エラー: \{err}")
  }
}

///|
/// 選ばれた Source / Sink を組み立てて回す。
/// ウェブダッシュボードがあるときは、Source が尽きても画面を見られるようにサーバを動かし続ける。
async fn start(options : CliOptions) -> Unit {
  let engine = @lib.Engine::new(
    config=@lib.EngineConfig::new(
      context=options.context,
      queue_limit=options.queue_limit,
      reaction_words=options.reaction_words,
      bundle=@lib.BundleConfig::new(
        window_ms=options.window_sec.to_int64() * 1000,
        threshold=options.threshold,
        metric=options.metric,
      ),
      pickup=@lib.PickupConfig::new(
        priority_threshold=options.priority_threshold,
        kind_floor=options.pickup_floor,
      ),
    ),
  )
  let sources : Array[&@lib.Source] = []
  for name in options.sources {
    match name {
      "stdin" =>
        sources.push(
          @stdin_source.StdinSource::new(source=options.stdin_source),
        )
      "replay" => {
        guard options.replay_path is Some(path) else {
          println(
            "--source replay には --replay <file.tsv> が必要です\n\n\{usage}",
          )
          return
        }
        sources.push(
          @replay_source.ReplaySource::new(path, speed=options.speed),
        )
      }
      "twitch" => {
        guard !options.twitch_channels.is_empty() else {
          println(
            "--source twitch には --twitch <channel> が必要です\n\n\{usage}",
          )
          return
        }
        for channel in options.twitch_channels {
          sources.push(@twitch_source.TwitchSource::new(channel))
        }
      }
      "youtube" => {
        guard options.youtube_video_id is Some(video_id) else {
          println(
            "--source youtube には --youtube <videoId> が必要です\n\n\{usage}",
          )
          return
        }
        guard @env.get_env_var("YOUTUBE_API_KEY") is Some(api_key) else {
          println(
            "--source youtube には環境変数 YOUTUBE_API_KEY が必要です",
          )
          return
        }
        sources.push(@youtube_source.YouTubeSource::new(video_id, api_key))
      }
      _ => {
        println("未対応の source: \{name}\n\n\{usage}")
        return
      }
    }
  }
  let mut web : @web_adapter.WebServer? = None
  for name in options.sinks {
    match name {
      "web" =>
        web = Some(
          @web_adapter.WebServer::new(
            engine,
            host=options.host,
            port=options.port,
            web_dir=options.web_dir,
          ),
        )
      "terminal" => engine.add_sink(@terminal_sink.TerminalSink::new())
      _ => {
        println("未対応の sink: \{name}\n\n\{usage}")
        return
      }
    }
  }
  let client = @jev.JevClient::from_env()
  @async.with_task_group(group => {
    if web is Some(web) {
      group.spawn_bg(() => web.serve())
    }
    @runtime.run(engine, client.judge_fn(), sources, workers=options.workers)
    let stats = engine.state(@async.now()).stats
    @runtime.log(
      "Source が終わりました: 受信 \{stats.received} / 早期判定 \{stats.early} / 相乗り \{stats.inherited} / Jev \{stats.sent}（失敗 \{stats.failed}）/ 落とした \{stats.dropped}",
    )
  })
}
