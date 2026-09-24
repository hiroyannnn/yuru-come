// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "hiroyannnn/yuru-come"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/hiroyannnn/yuru-come"

license = "Apache-2.0"

keywords = [
  "jev",
  "typesafe",
  "live-chat",
  "comment-viewer",
  "streaming",
  "youtube",
  "twitch",
]

preferred_target = "native"

description = "Loose comment viewer: bundles duplicate live-chat reactions and surfaces the comments a streamer should not miss, triaged by TypeSafe Jev"

import {
  "moonbitlang/async@0.22.1",
  "hiroyannnn/strsim@0.2.0",
  "hiroyannnn/yuru-kit@0.1.0",
}
