///|
/// 再接続までの待ち時間（ミリ秒）。失敗が続くごとに倍にし、`max_ms` で止める。
pub fn reconnect_delay_ms(
  failures : Int,
  base_ms? : Int = 1000,
  max_ms? : Int = 60_000,
) -> Int {
  let mut delay = base_ms
  for _ in 0..<failures {
    if delay >= max_ms {
      return max_ms
    }
    delay = delay * 2
  }
  if delay > max_ms {
    max_ms
  } else {
    delay
  }
}

///|
/// 切れる前の接続が十分に長くもっていたか。もっていたなら失敗の数を 0 に戻してすぐ再接続する。
pub fn connection_was_healthy(
  connected_ms~ : Int64,
  healthy_ms? : Int64 = 60_000,
) -> Bool {
  connected_ms >= healthy_ms
}
