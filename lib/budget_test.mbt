///|
/// 2026-09-24 00:00:00 UTC（ミリ秒）。
const DAY0 : Int64 = 1790208000000

///|
const DAY_MS : Int64 = 86_400_000

///|
test "1 日の上限まで使え、超えたら断る" {
  let budget = @lib.DailyBudget::new(limit=3)
  assert_true(budget.spend(DAY0))
  assert_true(budget.spend(DAY0 + 1))
  assert_true(budget.spend(DAY0 + 2))
  assert_false(budget.spend(DAY0 + 3))
  assert_eq(budget.used(DAY0 + 3), 3)
  assert_eq(budget.remaining(DAY0 + 3), 0)
}

///|
test "UTC の日付が変わったら使った数が戻る" {
  let budget = @lib.DailyBudget::new(limit=1)
  assert_true(budget.spend(DAY0 + DAY_MS - 1))
  assert_false(budget.spend(DAY0 + DAY_MS - 1))
  assert_true(budget.spend(DAY0 + DAY_MS))
  assert_eq(budget.remaining(DAY0 + DAY_MS), 0)
  assert_eq(budget.remaining(DAY0 + 2 * DAY_MS), 1)
}

///|
test "保存と復元（Durable Object のストレージに置くため）" {
  let budget = @lib.DailyBudget::new(limit=10)
  budget.spend(DAY0) |> ignore
  budget.spend(DAY0) |> ignore
  let restored = @lib.DailyBudget::restore(budget.dump(), limit=10)
  assert_eq(restored.used(DAY0), 2)
  // 壊れた保存データは空から始める
  assert_eq(@lib.DailyBudget::restore(Json::null(), limit=10).used(DAY0), 0)
}

///|
test "上限を変えて復元したら新しい上限に従う" {
  let budget = @lib.DailyBudget::new(limit=10)
  for _ in 0..<5 {
    budget.spend(DAY0) |> ignore
  }
  let smaller = @lib.DailyBudget::restore(budget.dump(), limit=4)
  assert_false(smaller.spend(DAY0))
}
