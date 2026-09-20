///|
test "一時的な失敗（429 と 5xx）だけを再試行の対象にする" {
  for code in [429, 500, 502, 503, 504] {
    assert_true(is_transient_status(code), msg=code.to_string())
  }
  for code in [200, 400, 401, 403, 404, 422] {
    assert_false(is_transient_status(code), msg=code.to_string())
  }
}

///|
test "エラーの表示にはステータスと本文の先頭が入り、長い本文は切る" {
  let short = HttpStatus(504, "Request timed out.").to_string()
  assert_true(short.contains("504") && short.contains("Request timed out."))
  let long = HttpStatus(500, "x".repeat(1000)).to_string()
  assert_true(long.char_length() < 300)
}
