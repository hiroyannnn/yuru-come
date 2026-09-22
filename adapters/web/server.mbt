///|
/// 配信者が自分で見るダッシュボードの HTTP サーバ。
///
/// - `GET /`            3 枠の画面（`/api/state` を 1 秒ごとにポーリング）
/// - `GET /overlay`     OBS のブラウザソース用（背景透過）。話題になった商品の QR とリンクを出す
/// - `GET /api/qr.svg?text=<URL>` その URL の QR コード
/// - `GET /api/state`   エンジンの全状態
/// - `POST /api/dismiss` `{"id": <項目 ID>, "action": "picked"|"skipped"}` 気になるコメントを消し、正解データとして記録する
///
/// 正解データ（拾った・スルー・期限切れ）は `labels_path` に JSONL で追記する。
pub struct WebServer {
  engine : @lib.Engine
  host : String
  port : Int
  web_dir : String
  /// 正解データの追記先。空なら書かない
  labels_path : String
}

///|
pub fn WebServer::new(
  engine : @lib.Engine,
  host? : String = "127.0.0.1",
  port? : Int = 8791,
  web_dir? : String = "web",
  labels_path? : String = "labels.jsonl",
) -> WebServer {
  { engine, host, port, web_dir, labels_path, }
}

///|
/// サーバを起動する。止まらないので戻らない。
pub async fn WebServer::serve(self : WebServer) -> Unit {
  let server = @http.Server(@socket.Addr::parse("\{self.host}:\{self.port}"))
  @runtime.log(
    "web: http://\{self.host}:\{self.port}/ でダッシュボードを開けます",
  )
  server.run_forever(allow_failure=true, (request, body, conn) => {
    self.handle(request, body, conn)
  })
}

///|
async fn WebServer::handle(
  self : WebServer,
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
  let path = match request.path.find("?") {
    Some(i) => request.path[:i].to_owned()
    None => request.path
  }
  match (request.meth, path) {
    (Get, "/") =>
      self.send_static(conn, "index.html", "text/html; charset=utf-8")
    (Get, "/style.css") =>
      self.send_static(conn, "style.css", "text/css; charset=utf-8")
    (Get, "/app.js") =>
      self.send_static(conn, "app.js", "text/javascript; charset=utf-8")
    (Get, "/overlay") =>
      self.send_static(conn, "overlay.html", "text/html; charset=utf-8")
    (Get, "/api/qr.svg") => send_qr(conn, query_param(request.path, "text"))
    (Get, "/api/state") => {
      let state = self.engine.state(@async.now())
      self.flush_labels()
      send_json(conn, 200, state.to_json())
    }
    (Post, "/api/dismiss") => self.handle_dismiss(body, conn)
    (Get, "/favicon.ico") => conn.send_response(204, "No Content")
    _ => send_json(conn, 404, { "error": "not found" })
  }
}

///|
async fn WebServer::handle_dismiss(
  self : WebServer,
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
  let json = @json.parse(body.read_all().text()) catch {
    _ => return send_json(conn, 400, { "error": "JSON が不正です" })
  }
  guard json is Object({ "id": Number(id, ..), .. } as body) else {
    return send_json(conn, 400, { "error": "id が必要です" })
  }
  let outcome : @lib.PickupOutcome = match body.get("action") {
    Some(String("skipped")) => Skipped
    _ => Picked
  }
  let ok = self.engine.resolve_pickup(id.to_int(), outcome, @async.now())
  self.flush_labels()
  send_json(conn, 200, { "ok": ok })
}

///|
/// 溜まった正解データを JSONL で追記する。失敗はログに出すだけ。
async fn WebServer::flush_labels(self : WebServer) -> Unit {
  let labels = self.engine.take_labels()
  guard !labels.is_empty() && !self.labels_path.is_empty() else { return }
  let lines = labels.map(label => label.to_json().stringify()).join("\n") + "\n"
  @fs.write_file(self.labels_path, lines, append=true, create_mode=OpenOrCreate) catch {
    err => @runtime.log("web: \{self.labels_path} に書けません: \{err}")
  }
}

///|
/// `web_dir` の静的ファイルを返す。毎回読むので編集が即反映される。
async fn WebServer::send_static(
  self : WebServer,
  conn : @http.ServerConnection,
  name : String,
  mime : String,
) -> Unit {
  let data = @fs.read_file("\{self.web_dir}/\{name}") catch {
    err => {
      @runtime.log("web: \{self.web_dir}/\{name} を読めません: \{err}")
      return send_json(conn, 500, { "error": "static file not found: \{name}" })
    }
  }
  conn.send_response(200, "OK", extra_headers=content_type(mime))
  conn.write(data)
}

///|
/// URL のクエリから 1 つ取り出す（パーセントデコード）。無ければ空。
fn query_param(path : String, name : String) -> String {
  guard path.find("?") is Some(q) else { return "" }
  for pair in path[q + 1:].split("&") {
    let (key, value) = match pair.find("=") {
      Some(i) => (pair[:i], pair[i + 1:])
      None => (pair, "")
    }
    if key == name {
      return percent_decode(value.to_owned())
    }
  }
  ""
}

///|
fn percent_decode(text : String) -> String {
  let bytes : Array[Byte] = []
  let chars = text.to_array()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '%' && i + 2 < chars.length() {
      match (hex_value(chars[i + 1]), hex_value(chars[i + 2])) {
        (Some(hi), Some(lo)) => {
          bytes.push((hi * 16 + lo).to_byte())
          i += 3
          continue
        }
        _ => ()
      }
    }
    if c == '+' {
      bytes.push(b' ')
    } else {
      for b in @utf8.encode(c.to_string()) {
        bytes.push(b)
      }
    }
    i += 1
  }
  @utf8.decode_lossy(Bytes::from_array(bytes))
}

///|
fn hex_value(c : Char) -> Int? {
  match c {
    '0'..='9' => Some(c.to_int() - '0')
    'a'..='f' => Some(c.to_int() - 'a' + 10)
    'A'..='F' => Some(c.to_int() - 'A' + 10)
    _ => None
  }
}

///|
async fn send_qr(conn : @http.ServerConnection, text : String) -> Unit {
  match @lib.qr_svg(text) {
    Some(svg) => {
      conn.send_response(200, "OK", extra_headers=content_type("image/svg+xml"))
      conn.write(svg)
    }
    None => send_json(conn, 400, { "error": "QR を生成できません" })
  }
}

///|
async fn send_json(
  conn : @http.ServerConnection,
  code : Int,
  json : Json,
) -> Unit {
  let reason = if code == 200 { "OK" } else { "Error" }
  conn.send_response(
    code,
    reason,
    extra_headers=content_type("application/json; charset=utf-8"),
  )
  conn.write(json.stringify())
}

///|
fn content_type(value : String) -> @http.Headers {
  Map::from_array([
    (@http.CaseInsensitiveString("Content-Type"), value),
    (@http.CaseInsensitiveString("Cache-Control"), "no-store"),
  ])
}
