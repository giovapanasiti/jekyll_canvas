# frozen_string_literal: true

# Runs in its own process so jekyll-polyglot is never loaded: builds a site without polyglot.
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
$stdout = $stderr
require "jekyll_canvas"
require "tmpdir"
require "json"

Dir.mktmpdir do |cache|
  builder = JekyllCanvas::Builder.new(root: ARGV[0], cache_dir: cache)
  ok = builder.build
  out = { ok: ok, error: builder.error, languages: builder.info[:languages],
          records: builder.records.map { |r| { url: r.url, lang: r.lang, strings: r.strings.values.map { |s| s[:keypath] } } },
          html: File.read(File.join(cache, "site/index.html")) }
  STDOUT.puts JSON.generate(out)
end
