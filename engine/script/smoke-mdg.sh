#!/usr/bin/env bash
# Smoke test against a throw-away clone of the reference site (the original is never touched).
#   engine/script/smoke-mdg.sh [path-to-reference-site]   (KEEP=1 keeps the clone and prints its path)
set -euo pipefail

ENGINE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$HOME/Projects/mdg/nuovo_sito_mdg}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/jc-smoke.XXXXXX")"
SITE="$TMP/site"
PID=""

cleanup() {
  [ -n "$PID" ] && kill "$PID" 2>/dev/null && wait "$PID" 2>/dev/null || true
  if [ "${KEEP:-0}" = "1" ]; then echo "kept: $TMP"; else rm -rf "$TMP"; fi
}
trap cleanup EXIT

echo "== cloning $SRC"
git clone -q "$SRC" "$SITE"

echo "== starting the engine"
cd "$SITE"
BUNDLE=()
[ -f Gemfile ] && BUNDLE=(bundle exec)
"${BUNDLE[@]}" ruby -I"$ENGINE/lib" "$ENGINE/exe/jekyll-canvas-server" --site "$SITE" --cache-dir "$TMP/cache" >"$TMP/out" 2>"$TMP/err" &
PID=$!

READY=""
for _ in $(seq 1 240); do
  READY="$(grep -m1 '^JEKYLL_CANVAS_READY ' "$TMP/out" || true)"
  [ -n "$READY" ] && break
  kill -0 "$PID" 2>/dev/null || { echo "engine exited early:"; tail -30 "$TMP/err"; exit 1; }
  sleep 0.5
done
[ -n "$READY" ] || { echo "timeout waiting for the engine"; tail -30 "$TMP/err"; exit 1; }

URL="$(echo "$READY" | cut -d' ' -f2)"
BASE="${URL%%/__jc/*}"
TOKEN="${URL##*token=}"
api() { curl -fsS -H "X-JC-Token: $TOKEN" "$BASE/__jc/api/$1"; }

echo "== state:  $(api state)"
api site >"$TMP/site.json"
api "page?url=/" >"$TMP/page-en.json"
api "page?url=/it/" >"$TMP/page-it.json"

ruby -Eutf-8:utf-8 -rjson -e '
  site = JSON.parse(File.read(ARGV[0]))
  puts "== site:   #{site["name"]} (#{site["title"]}) languages=#{site["languages"].join(",")} git=#{site["git"]}"
  site["groups"].each { |g| puts "   group %-14s items=%d can_create=%s" % [g["id"], g["items"].length, g["can_create"]] }
  { "/" => ARGV[1], "/it/" => ARGV[2] }.each do |url, file|
    page = JSON.parse(File.read(file))
    strings = page["strings"]
    data = strings.count { |s| s["source"] == "data" }
    home = strings.count { |s| s["file"].start_with?("_data/i18n/") && s["keypath"].first == "home" }
    sib = strings.count { |s| !s["siblings"].empty? }
    puts "== page #{url}: file=#{page["file"]} strings=#{strings.length} (data=#{data}, i18n home.*=#{home}, with siblings=#{sib}) layouts=#{page["layouts"].length} includes=#{page["includes"].length} translations=#{page["translations"].map { |t| t["url"] }.join(" ")}"
  end
' "$TMP/site.json" "$TMP/page-en.json" "$TMP/page-it.json"

echo "== git status of the clone after the build:"
git -C "$SITE" status --short | sed 's/^/   /'
echo "   (empty above = clean)"
echo "== OK"
