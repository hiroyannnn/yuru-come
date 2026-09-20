///|
/// コア（lib）の公開 API をルートパッケージから直接使えるように再エクスポートする。
pub using @lib {
  type Comment,
  type Token,
  type BundleMetric,
  type BundleConfig,
  type BundleHit,
  type BundleSummary,
  type Bundler,
  participant_id,
  normalize,
  normalize_tokens,
  unify_width,
  compress_runs,
}
