.PHONY: test check assets build release

# 全ターゲットのテスト
test:
	moon test --target all

# コミット前の確認（.mbti の更新、整形、埋め込み資産の同期、型検査）
check:
	moon info
	moon fmt
	python3 scripts/embed_assets.py --check
	moon check --target all

# web/ を編集したら実行して adapters/web/assets.mbt を作り直す
assets:
	python3 scripts/embed_assets.py

# このマシン向けのリリースビルド（_build/native/release/build/cmd/yuru-come/yuru-come.exe）
build:
	moon build --target native --release

# 使い方: make release v=0.2.0
# バージョンを moon.mod と cmd/yuru-come/version.mbt に書き、コミットして GitHub Release を作る。
# Release が公開されると .github/workflows/release.yml がバイナリを添付し、mooncakes.io に publish する。
release:
	@test -n "$(v)" || (echo "Usage: make release v=0.2.0" && exit 1)
	@git diff --quiet || (echo "コミットしていない変更があります" && exit 1)
	@$(MAKE) check
	@moon test --target all
	@moon publish --dry-run
	sed -i '' 's/^version = "[^"]*"/version = "$(v)"/' moon.mod
	sed -i '' 's/^pub const VERSION : String = "[^"]*"/pub const VERSION : String = "$(v)"/' cmd/yuru-come/version.mbt
	git add moon.mod cmd/yuru-come/version.mbt
	git commit -m "release: v$(v)"
	git push
	gh release create "v$(v)" --generate-notes --title "v$(v)"
