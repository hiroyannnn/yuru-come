///|
/// 評価セットの 1 行。
struct EvalRow {
  kind : @lib.Kind
  /// 配信者が拾うべきか
  pickup : Bool
  text : String
} derive(Debug, Eq)

///|
/// `kind<TAB>1|0<TAB>コメント` を読む。`#` で始まる行、空行、形式に合わない行は None。
fn parse_eval_line(line : String) -> EvalRow? {
  let line = line.trim(chars="\r\n").to_owned()
  guard !line.has_prefix("#") else { return None }
  guard line.find("\t") is Some(first) else { return None }
  let rest = line[first + 1:]
  guard rest.find("\t") is Some(second) else { return None }
  guard @lib.Kind::from_key(line[:first].to_owned()) is Some(kind) else {
    return None
  }
  let pickup = match rest[:second] {
    "1" => true
    "0" => false
    _ => return None
  }
  let text = rest[second + 1:].to_owned()
  guard !text.is_empty() else { return None }
  Some({ kind, pickup, text, })
}

///|
/// 表の行と列に出す kind の順。
let kind_order : Array[@lib.Kind] = [..@lib.jev_kinds, Reaction, Unjudged]

///|
/// 混同行列（正解 × 判定）。
struct Confusion {
  cells : Map[String, Int]
}

///|
fn Confusion::new() -> Confusion {
  { cells: Map([]), }
}

///|
fn cell_key(expected : @lib.Kind, predicted : @lib.Kind) -> String {
  "\{expected.key()}>\{predicted.key()}"
}

///|
fn Confusion::add(
  self : Confusion,
  expected : @lib.Kind,
  predicted : @lib.Kind,
) -> Unit {
  let key = cell_key(expected, predicted)
  self.cells[key] = self.cells.get(key).unwrap_or(0) + 1
}

///|
fn Confusion::count(
  self : Confusion,
  expected : @lib.Kind,
  predicted : @lib.Kind,
) -> Int {
  self.cells.get(cell_key(expected, predicted)).unwrap_or(0)
}

///|
fn Confusion::total(self : Confusion) -> Int {
  self.cells.values().fold(init=0, (sum, n) => sum + n)
}

///|
fn Confusion::correct(self : Confusion) -> Int {
  kind_order.fold(init=0, (sum, kind) => sum + self.count(kind, kind))
}

///|
fn Confusion::accuracy(self : Confusion) -> Double {
  ratio(self.correct(), self.total())
}

///|
/// Markdown の表にする。行は正解に出てきた kind、列は正解か判定に出てきた kind。
fn Confusion::render(self : Confusion) -> String {
  let rows = kind_order.filter(expected => {
    kind_order.iter().any(predicted => self.count(expected, predicted) > 0)
  })
  // 列は、正解か判定のどちらかに出てきた kind
  let columns = kind_order.filter(kind => {
    kind_order
    .iter()
    .any(other => self.count(other, kind) > 0 || self.count(kind, other) > 0)
  })
  let lines : Array[String] = []
  let header = columns.map(kind => kind.key()).join(" | ")
  lines.push("| 正解＼判定 | \{header} |")
  lines.push("| --- | \{columns.map(_ => "---").join(" | ")} |")
  for expected in rows {
    let cells = columns
      .map(predicted => self.count(expected, predicted).to_string())
      .join(" | ")
    lines.push("| \{expected.key()} | \{cells} |")
  }
  lines.join("\n")
}

///|
/// 「拾うべき」の当たり外れ。
struct PickupScore {
  mut true_positive : Int
  mut false_positive : Int
  mut false_negative : Int
}

///|
fn PickupScore::new() -> PickupScore {
  { true_positive: 0, false_positive: 0, false_negative: 0, }
}

///|
fn PickupScore::add(
  self : PickupScore,
  expected~ : Bool,
  predicted~ : Bool,
) -> Unit {
  match (expected, predicted) {
    (true, true) => self.true_positive += 1
    (false, true) => self.false_positive += 1
    (true, false) => self.false_negative += 1
    (false, false) => ()
  }
}

///|
/// 拾うと判定したもののうち、本当に拾うべきだった割合。
fn PickupScore::precision(self : PickupScore) -> Double {
  ratio(self.true_positive, self.true_positive + self.false_positive)
}

///|
/// 拾うべきもののうち、拾えた割合。
fn PickupScore::recall(self : PickupScore) -> Double {
  ratio(self.true_positive, self.true_positive + self.false_negative)
}

///|
fn ratio(numerator : Int, denominator : Int) -> Double {
  if denominator == 0 {
    0.0
  } else {
    numerator.to_double() / denominator.to_double()
  }
}

///|
/// 最近傍法のパーセンタイル。空なら 0。
fn percentile(values : Array[Int], p : Int) -> Int {
  guard values.length() > 0 else { return 0 }
  let sorted = values.copy()
  sorted.sort()
  let rank = (p * sorted.length() + 99) / 100
  sorted[if rank < 1 { 0 } else { rank - 1 }]
}
