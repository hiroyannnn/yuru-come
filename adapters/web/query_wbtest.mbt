///|
test "クエリから値を取り出し、パーセントエンコードと + を戻す" {
  assert_eq(
    query_param("/api/qr.svg?text=https%3A%2F%2Fexample.com%2Fmic", "text"),
    "https://example.com/mic",
  )
  assert_eq(
    query_param("/api/qr.svg?a=1&text=%E3%83%9E%E3%82%A4%E3%82%AF+x", "text"),
    "マイク x",
  )
  assert_eq(query_param("/api/qr.svg", "text"), "")
  assert_eq(query_param("/api/qr.svg?other=1", "text"), "")
}
