///|
test "再接続の待ち時間は失敗が続くごとに倍になり、上限で止まる" {
  assert_eq(@lib.reconnect_delay_ms(0), 1000)
  assert_eq(@lib.reconnect_delay_ms(1), 2000)
  assert_eq(@lib.reconnect_delay_ms(2), 4000)
  assert_eq(@lib.reconnect_delay_ms(5), 32000)
  assert_eq(@lib.reconnect_delay_ms(6), 60000)
  assert_eq(@lib.reconnect_delay_ms(100), 60000)
}

///|
test "待ち時間の初期値と上限は変えられる" {
  assert_eq(@lib.reconnect_delay_ms(0, base_ms=500, max_ms=3000), 500)
  assert_eq(@lib.reconnect_delay_ms(3, base_ms=500, max_ms=3000), 3000)
}

///|
test "接続が一定時間もっていたら、失敗の数え直しになる" {
  // 60 秒以上つながっていた切断は「たまたま」なので、次はすぐ再接続する
  assert_true(@lib.connection_was_healthy(connected_ms=60_000))
  assert_false(@lib.connection_was_healthy(connected_ms=59_999))
  assert_false(
    @lib.connection_was_healthy(connected_ms=1_000, healthy_ms=5_000),
  )
  assert_true(@lib.connection_was_healthy(connected_ms=5_000, healthy_ms=5_000))
}
