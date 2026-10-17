# frozen_string_literal: true

require "support/harness"
require "rbconfig"

class IntegrationTest < Minitest::Test
  def setup
    @h = Harness.new
    @before = @h.listing
    @h.build!
  end

  def teardown
    @h.close
  end

  def strings(url)
    code, page = @h.page(url)
    assert_equal 200, code, page.inspect
    page["strings"]
  end

  def find_string(strings, file, keypath)
    strings.find { |s| s["file"] == file && s["keypath"] == keypath }
  end

  # --- tracing --------------------------------------------------------------------------------

  def test_home_strings_for_both_languages
    en = strings("/")
    s = find_string(en, "_data/i18n/en.yml", %w[home hero title])
    assert s, "hero title missing: #{en.map { |x| [x['file'], x['keypath']] }.inspect}"
    assert_equal "We build AI products", s["value"]
    assert_equal "data", s["source"]
    assert s["editable"]
    assert find_string(en, "_data/i18n/en.yml", ["home", "items", 1, "note"])
    assert find_string(en, "_data/nav.yml", [1, "label", "en"])
    assert find_string(en, "index.html", ["title"])
    assert_nil find_string(en, "_data/i18n/it.yml", %w[home hero title])

    it = strings("/it/")
    s = find_string(it, "_data/i18n/it.yml", %w[home hero title])
    assert_equal "Costruiamo prodotti AI", s["value"]
    assert_equal [{ "lang" => "en", "file" => "_data/i18n/en.yml", "keypath" => %w[home hero title], "value" => "We build AI products" }],
                 s["siblings"]
    assert find_string(it, "_data/nav.yml", [1, "label", "it"])
  end

  def test_siblings_by_keypath_language_segment
    s = find_string(strings("/it/"), "_data/nav.yml", [1, "label", "it"])
    assert_equal [{ "lang" => "en", "file" => "_data/nav.yml", "keypath" => [1, "label", "en"], "value" => "About us" }], s["siblings"]
  end

  def test_siblings_by_page_id
    s = find_string(strings("/it/progetti/alfa/"), "_projects/it/alfa.md", ["summary"])
    assert_equal "Un breve riassunto di alfa", s["value"]
    assert_equal "front_matter", s["source"]
    assert_equal [{ "lang" => "en", "file" => "_projects/alpha.md", "keypath" => ["summary"], "value" => "A short summary of alpha" }],
                 s["siblings"]
  end

  def test_project_page_document
    code, page = @h.page("/projects/alpha/")
    assert_equal 200, code
    assert_equal "_projects/alpha.md", page["file"]
    assert_equal "document", page["kind"]
    assert_equal "projects", page["collection"]
    assert_equal "markdown", page["format"]
    assert_equal "en", page["lang"]
    assert_equal "Alpha Project", page["title"]
    assert_equal 11, page["body_start_line"]
    assert_equal %w[_layouts/project.html _layouts/default.html], page["layouts"]
    assert_equal ["_includes/header.html"], page["includes"]
    assert_equal "A short summary of alpha", page["front_matter"]["data"]["summary"]
    assert_equal [{ "lang" => "en", "url" => "/projects/alpha/", "file" => "_projects/alpha.md" },
                  { "lang" => "it", "url" => "/it/progetti/alfa/", "file" => "_projects/it/alfa.md" }], page["translations"]
    assert find_string(page["strings"], "_projects/alpha.md", ["summary"])
    assert find_string(page["strings"], "_projects/alpha.md", ["stack", 0])
    refute find_string(page["strings"], "_projects/alpha.md", ["lang"]), "excluded keys must not be traced"
    refute find_string(page["strings"], "_projects/alpha.md", ["permalink"])
  end

  def test_page_translations_for_single_source_page
    _, page = @h.page("/it")
    assert_equal "/it/", page["url"]
    assert_equal [{ "lang" => "en", "url" => "/", "file" => "index.html" }, { "lang" => "it", "url" => "/it/", "file" => "index.html" }],
                 page["translations"]
  end

  def test_data_jc_line_matches_source_lines
    html = File.read(File.join(@h.cache, "site/projects/alpha/index.html"), encoding: "UTF-8")
    source = @h.read("_projects/alpha.md").lines
    found = html.scan(/<(\w+)[^>]*data-jc-line="(\d+)"[^>]*>([^<\n]*)/)
    assert_equal 5, found.length, found.inspect
    expectations = { "h2" => "## Overview", "p" => nil, "ul" => "- one", "figure" => "<figure>" }
    found.each do |tag, line, text|
      src = source[line.to_i - 1].to_s.chomp
      case tag
      when "h2" then assert_equal expectations["h2"], src
      when "ul" then assert_equal expectations["ul"], src
      when "figure" then assert_equal expectations["figure"], src
      when "p" then assert src.start_with?(text.lines.first.to_s.strip[0, 12]), "line #{line} is #{src.inspect}, html #{text.inspect}"
      end
    end
    italian = File.read(File.join(@h.cache, "site/it/progetti/alfa/index.html"), encoding: "UTF-8")
    line = italian[/data-jc-line="(\d+)"[^>]*>Panoramica/, 1].to_i
    assert_equal "## Panoramica", @h.read("_projects/it/alfa.md").lines[line - 1].chomp
  end

  def test_data_jc_line_only_on_own_body
    listing = File.read(File.join(@h.cache, "site/projects/index.html"), encoding: "UTF-8")
    refute_includes listing, "data-jc-line", "other documents' content and excerpts must not be annotated"
    refute_includes File.read(File.join(@h.cache, "site/index.html"), encoding: "UTF-8"), "data-jc-line"
    assert_includes File.read(File.join(@h.cache, "site/blog/hello-world/index.html"), encoding: "UTF-8"), "data-jc-line=\"9\""
  end

  def test_md_block_endpoint
    code, block = @h.get_json("/__jc/api/md-block?file=_projects/alpha.md&line=13")
    assert_equal 200, code
    assert_equal({ "file" => "_projects/alpha.md", "start_line" => 13, "end_line" => 14, "type" => "p", "header_level" => nil,
                   "markdown" => "First paragraph of alpha.\nStill the first paragraph." }, block)
    _, heading = @h.get_json("/__jc/api/md-block?file=_projects/alpha.md&line=11")
    assert_equal ["header", 2, "## Overview"], [heading["type"], heading["header_level"], heading["markdown"]]
    _, fig = @h.get_json("/__jc/api/md-block?file=_projects/alpha.md&line=19")
    assert_equal ["html_element", 19, 22], [fig["type"], fig["start_line"], fig["end_line"]]
    code, = @h.get_json("/__jc/api/md-block?file=_projects/alpha.md&line=2")
    assert_equal 404, code
  end

  def test_locate_endpoint
    code, res = @h.post_json("/__jc/api/locate", url: "/about", text: "We are a small team that loves Jekyll & Ruby.")
    assert_equal 200, code
    c = res["candidates"].first
    assert_equal "about.html", c["file"]
    assert_equal @h.read("about.html")[c["start"]...c["end"]], c["old_text"]
    _, res = @h.post_json("/__jc/api/locate", url: "/it/", text: "Hardcoded header text")
    assert_equal ["_includes/header.html"], res["candidates"].map { |x| x["file"] }
    _, res = @h.post_json("/__jc/api/locate", url: "/about/", text: "no such words")
    assert_equal [], res["candidates"]
  end

  # --- API basics -------------------------------------------------------------------------------------

  def test_token_required_for_api_but_not_site_or_ui
    assert_equal 403, @h.get("/__jc/api/state", token: false).code.to_i
    body = JSON.parse(@h.get("/__jc/api/state", token: false).body)
    assert_equal({ "error" => "forbidden" }, body.slice("error"))
    assert_equal 200, @h.get("/", token: false).code.to_i
    assert_equal 200, @h.get("/__jc/", token: false).code.to_i
    assert_includes @h.get("/__jc/", token: false).body, "Jekyll Canvas"
  end

  def test_state_and_site
    _, state = @h.get_json("/__jc/api/state")
    assert_equal({ "build_id" => 1, "building" => false, "error" => nil }, state.slice("build_id", "building", "error"))
    assert_kind_of Integer, state["last_build_ms"]
    _, site = @h.get_json("/__jc/api/site")
    assert_equal %w[en it], site["languages"]
    assert_equal "en", site["default_lang"]
    assert_equal true, site["git"]
    assert_equal "Fixture Site", site["title"]
    assert_equal %w[pages posts projects], site["groups"].map { |g| g["id"] }
    pages = site["groups"][0]
    assert_equal false, pages["can_create"]
    assert_equal %w[/ /about/ /it/ /it/chi-siamo/ /it/projects/ /projects/].sort, pages["items"].map { |i| i["url"] }.sort
    posts = site["groups"][1]
    assert_equal ["Articoli", "posts", true], [posts["label"], posts["collection"], posts["can_create"]]
    assert_equal %w[/it/articoli/ciao-mondo/ /blog/hello-world/], posts["items"].map { |i| i["url"] }
    projects = site["groups"][2]
    assert_equal %w[en it], projects["items"].map { |i| i["lang"] }.sort
  end

  def test_unknown_page_and_paths
    code, body = @h.page("/nope/")
    assert_equal [404, "not_found", false], [code, body["code"], body["ok"]]
    code, body = @h.get_json("/__jc/api/file?file=../etc/passwd")
    assert_equal [403, "forbidden"], [code, body["code"]]
    code, = @h.get_json("/__jc/api/file?file=.git/config")
    assert_equal 403, code
    code, file = @h.get_json("/__jc/api/file?file=about.html")
    assert_equal 200, code
    assert_includes file["content"], "small team"
  end

  def test_site_files_served
    res = @h.get("/it/", token: false)
    assert_equal "no-store", res["Cache-Control"]
    assert_includes res.body, "Costruiamo prodotti AI"
    assert_includes @h.get("/about", token: false).body, "small team" if @h.get("/about", token: false).code == "200"
    assert_equal "301", @h.get("/it", token: false).code
    res = @h.get("/does/not/exist/", token: false)
    assert_equal "404", res.code
    assert_includes %w[400 404], @h.get("/%2e%2e/%2e%2e/etc/passwd", token: false).code
    assert_includes %w[400 404], @h.get("/..%2f..%2fetc/passwd", token: false).code
  end

  # --- edits ----------------------------------------------------------------------------------------

  def test_edit_yaml_data_changes_exactly_one_line
    code, res = @h.edit(op: "yaml", file: "_data/i18n/it.yml", keypath: %w[home hero title],
                        old: "Costruiamo prodotti AI", new: "Costruiamo prodotti AI migliori")
    assert_equal 200, code, res.inspect
    assert_equal [true, 2, nil], [res["ok"], res["build_id"], res["error"]]
    assert_kind_of Integer, res["build_ms"]
    diff = @h.git("diff", "-U0", "--", "_data/i18n/it.yml").lines.grep(/\A[+-][^+-]/)
    assert_equal ["-    title: Costruiamo prodotti AI   # tieni questo commento\n",
                  "+    title: Costruiamo prodotti AI migliori   # tieni questo commento\n"], diff
    assert_includes @h.get("/it/", token: false).body, "Costruiamo prodotti AI migliori"
    assert_equal "2", @h.get_json("/__jc/api/state")[1]["build_id"].to_s
  end

  def test_edit_yaml_unicode_via_http
    code, res = @h.edit(op: "yaml", file: "_data/i18n/it.yml", keypath: %w[home hero subtitle], old: "Parlaci oggi",
                        new: "Parliamo di perché è così \u{1F680}")
    assert_equal 200, code, res.inspect
    assert_includes @h.read("_data/i18n/it.yml"), "subtitle: 'Parliamo di perché è così \u{1F680}'"
  end

  def test_edit_yaml_front_matter_and_add_key
    code, = @h.edit(op: "yaml", file: "_projects/alpha.md", keypath: ["summary"], old: "A short summary of alpha", new: "Edited: summary")
    assert_equal 200, code
    assert_includes @h.read("_projects/alpha.md"), "summary: \"Edited: summary\"\n"
    assert_equal 1, @h.git("diff", "-U0", "--", "_projects/alpha.md").lines.grep(/\A\+[^+]/).length
    code, = @h.edit(op: "yaml", file: "_projects/alpha.md", keypath: ["subtitle"], new: "Brand new")
    assert_equal 200, code
    assert_includes @h.read("_projects/alpha.md"), "cover: /assets/img/alpha.webp\nsubtitle: Brand new\n---\n"
    code, = @h.edit(op: "yaml", file: "_projects/alpha.md", keypath: ["stack"], old: %w[Ruby Rails], new: %w[Ruby Rails Hotwire])
    assert_equal 200, code
    assert_includes @h.read("_projects/alpha.md"), "stack: [Ruby, Rails, Hotwire]\n"
    assert_includes @h.get("/projects/alpha/", token: false).body, "<li>Hotwire</li>"
  end

  def test_edit_yaml_conflicts_write_nothing
    before = @h.read("_data/i18n/it.yml")
    code, res = @h.edit(op: "yaml", file: "_data/i18n/it.yml", keypath: %w[home hero title], old: "Stale", new: "x")
    assert_equal [409, "conflict"], [code, res["code"]]
    assert_equal before, @h.read("_data/i18n/it.yml")
    assert_equal 1, @h.get_json("/__jc/api/state")[1]["build_id"]
  end

  def test_edit_literal
    src = @h.read("about.html")
    start = src.index("We are a small team")
    finish = src.index("</p>", start)
    old = src[start...finish]
    code, res = @h.edit(op: "literal", file: "about.html", start: start, end: finish, old_text: old,
                        new_text: "We are <a> team & more")
    assert_equal 200, code, res.inspect
    assert_includes @h.read("about.html"), "<p>We are &lt;a&gt; team &amp; more</p>"
    assert_equal 2, res["build_id"]
    code, res = @h.edit(op: "literal", file: "about.html", start: start, end: finish, old_text: old, new_text: "x")
    assert_equal [409, "conflict"], [code, res["code"]]
    liquid = @h.read("about.html").index("{{ page.title }}")
    code, res = @h.edit(op: "literal", file: "about.html", start: liquid, end: liquid + 6, old_text: "{{ pag", new_text: "x")
    assert_equal [422, "invalid"], [code, res["code"]]
  end

  def test_edit_md_block_replace_and_delete
    code, res = @h.edit(op: "md_block", file: "_projects/alpha.md", start_line: 13, end_line: 14,
                        old_markdown: "First paragraph of alpha.\nStill the first paragraph.",
                        new_markdown: "Rewritten paragraph.")
    assert_equal 200, code, res.inspect
    lines = @h.read("_projects/alpha.md").lines
    assert_equal "Rewritten paragraph.\n", lines[12]
    assert_equal "\n", lines[13]
    assert_equal "- one\n", lines[15 - 1]
    html = @h.get("/projects/alpha/", token: false).body
    assert_includes html, "data-jc-line=\"13\">Rewritten paragraph."
    assert_includes html, "<ul data-jc-line=\"15\">"

    code, res = @h.edit(op: "md_block", file: "_projects/alpha.md", start_line: 13, end_line: 14, old_markdown: "wrong", new_markdown: "x")
    assert_equal [409, "conflict"], [code, res["code"]]

    code, = @h.edit(op: "md_block", file: "_projects/alpha.md", start_line: 13, end_line: 13, old_markdown: "Rewritten paragraph.", new_markdown: "")
    assert_equal 200, code
    assert_equal "- one\n", @h.read("_projects/alpha.md").lines[12]
  end

  def test_edit_body
    code, res = @h.edit(op: "body", file: "_posts/2026-01-10-hello-world.md", old_body: "Hello from the first post.\n",
                        new_body: "# New\n\nWhole new body\n\n\n")
    assert_equal 200, code, res.inspect
    content = @h.read("_posts/2026-01-10-hello-world.md")
    assert content.end_with?("---\n\n# New\n\nWhole new body\n"), content.inspect
    code, res = @h.edit(op: "body", file: "_posts/2026-01-10-hello-world.md", old_body: "stale", new_body: "x")
    assert_equal [409, "conflict"], [code, res["code"]]
    assert_includes @h.get("/blog/hello-world/", token: false).body, "Whole new body"
  end

  def test_edit_front_matter_raw
    code, res = @h.edit(op: "front_matter_raw", file: "_posts/2026-01-10-hello-world.md",
                        new_yaml: "title: Renamed\nlang: en\nlang-exclusive: [en]\npermalink: /blog/hello-world/\n")
    assert_equal 200, code, res.inspect
    assert_includes @h.read("_posts/2026-01-10-hello-world.md"), "---\ntitle: Renamed\nlang: en\nlang-exclusive: [en]\npermalink: /blog/hello-world/\n---\n"
    code, res = @h.edit(op: "front_matter_raw", file: "_posts/2026-01-10-hello-world.md", new_yaml: "- not\n- a mapping\n")
    assert_equal [422, "invalid"], [code, res["code"]]
  end

  def test_edit_rejects_bad_requests
    code, res = @h.edit(op: "nope", file: "about.html")
    assert_equal [422, "invalid"], [code, res["code"]]
    code, res = @h.edit(op: "yaml", file: "../outside.yml", keypath: ["a"], new: "b")
    assert_equal [403, "forbidden"], [code, res["code"]]
    code, res = @h.edit(op: "yaml", file: "missing.yml", keypath: ["a"], new: "b")
    assert_equal 404, code
  end

  def test_build_failure_keeps_last_good_build
    @h.write("_layouts/default.html", "{% if %}broken")
    code, res = @h.edit(op: "yaml", file: "_data/i18n/it.yml", keypath: %w[home hero subtitle], old: "Parlaci oggi", new: "Nuovo")
    assert_equal 200, code
    refute_nil res["error"]
    _, state = @h.get_json("/__jc/api/state")
    refute_nil state["error"]
    assert_equal 1, state["build_id"]
    assert_includes @h.get("/it/", token: false).body, "Parlaci oggi", "previous build must keep being served"
    assert_includes @h.read("_data/i18n/it.yml"), "Nuovo", "the write is kept"
    @h.git("checkout", "--", "_layouts/default.html")
    code, res = @h.post_json("/__jc/api/rebuild", {})
    assert_equal 200, code
    assert_equal [true, nil], [res["ok"], res["error"]]
    assert_equal 2, res["build_id"]
    assert_includes @h.get("/it/", token: false).body, "Nuovo"
  end

  # --- new documents ------------------------------------------------------------------------------------

  def test_new_project_in_italian_uses_italian_template
    code, res = @h.post_json("/__jc/api/new", collection: "projects", lang: "it", title: "Il mio Progetto è già così", slug: nil, date: nil)
    assert_equal 200, code, res.inspect
    assert_equal "_projects/it/il-mio-progetto-e-gia-cosi.md", res["file"]
    assert_equal "/it/progetti/il-mio-progetto-e-gia-cosi/", res["url"]
    assert_equal <<~MD, @h.read(res["file"])
      ---
      title: Il mio Progetto è già così
      lang: it
      page_id: il-mio-progetto-e-gia-cosi
      permalink: /progetti/il-mio-progetto-e-gia-cosi/
      summary: ""
      stack: []
      cover: ""
      ---

      Scrivi qui il testo.
    MD
    assert_includes @h.get(res["url"], token: false).body, "Scrivi qui il testo."
    code, res2 = @h.post_json("/__jc/api/new", collection: "projects", lang: "it", title: "Il mio Progetto è già così")
    assert_equal [409, "conflict"], [code, res2["code"]]
  end

  def test_new_post_english
    code, res = @h.post_json("/__jc/api/new", collection: "posts", lang: "en", title: "My Post", slug: "my-post", date: "2026-10-17")
    assert_equal 200, code, res.inspect
    assert_equal "_posts/2026-10-17-my-post.md", res["file"]
    assert_equal "/blog/my-post/", res["url"]
    assert_equal <<~MD, @h.read(res["file"])
      ---
      title: My Post
      lang: en
      lang-exclusive: [en]
      permalink: /blog/my-post/
      categories: []
      date: 2026-10-17
      ---

      Scrivi qui il testo.
    MD
  end

  def test_new_rejects_bad_input
    code, res = @h.post_json("/__jc/api/new", collection: "posts", lang: "en", title: "  ")
    assert_equal [422, "invalid"], [code, res["code"]]
    code, res = @h.post_json("/__jc/api/new", collection: "posts", lang: "en", title: "x", date: "17/10/2026")
    assert_equal [422, "invalid"], [code, res["code"]]
  end

  # --- media ----------------------------------------------------------------------------------------------

  def test_media_upload_and_list
    FileUtils.mkdir_p(@h.path("assets/img/blog"))
    File.binwrite(@h.path("assets/img/blog/x.webp"), "webp-bytes")
    File.binwrite(@h.path("assets/note.txt"), "no image")
    code, res = @h.upload("/__jc/api/media", "Mia Foto è bella.PNG", "png-bytes")
    assert_equal 200, code, res.inspect
    assert_equal ["/assets/img/uploads/mia-foto-e-bella.png", "assets/img/uploads/mia-foto-e-bella.png"], [res["src"], res["file"]]
    assert_equal "png-bytes", File.binread(@h.path(res["file"]))
    _, res2 = @h.upload("/__jc/api/media", "Mia Foto è bella.PNG", "again")
    assert_equal "assets/img/uploads/mia-foto-e-bella-2.png", res2["file"]
    code, = @h.upload("/__jc/api/media", "evil.php", "x")
    assert_equal 422, code

    _, list = @h.get_json("/__jc/api/media")
    assert_equal "assets/img/uploads", list["uploads_dir"]
    files = list["data"].map { |d| d["file"] }
    assert_includes files, "assets/img/blog/x.webp"
    assert_includes files, "assets/img/uploads/mia-foto-e-bella.png"
    refute_includes files, "assets/note.txt"
    entry = list["data"].find { |d| d["file"] == "assets/img/blog/x.webp" }
    assert_equal ["/assets/img/blog/x.webp", "x.webp", 10], [entry["src"], entry["name"], entry["size"]]
    assert_equal 200, @h.get("/assets/img/uploads/mia-foto-e-bella.png", token: false).code.to_i
  end

  def test_media_uploads_dir_from_config
    @h.write(".jekyll-canvas.yml", "uploads_dir: media/up\n")
    code, res = @h.upload("/__jc/api/media", "a.png", "x")
    assert_equal 200, code
    assert_equal "media/up/a.png", res["file"]
  end

  # --- git --------------------------------------------------------------------------------------------------

  def test_git_status_diff_discard_commit
    _, st = @h.get_json("/__jc/api/git/status")
    assert_equal [true, []], [st["git"], st["files"]]
    refute_empty st["branch"]

    @h.edit(op: "yaml", file: "_data/i18n/it.yml", keypath: %w[home hero subtitle], old: "Parlaci oggi", new: "Scrivici")
    @h.post_json("/__jc/api/new", collection: "posts", lang: "en", title: "Draft", date: "2026-10-17")
    _, st = @h.get_json("/__jc/api/git/status")
    assert_equal [{ "path" => "_data/i18n/it.yml", "status" => "M" }, { "path" => "_posts/2026-10-17-draft.md", "status" => "??" }].sort_by { |f| f["path"] },
                 st["files"].sort_by { |f| f["path"] }

    _, d = @h.get_json("/__jc/api/git/diff?file=_data/i18n/it.yml")
    assert_includes d["diff"], "+    subtitle: 'Scrivici'"
    _, d = @h.get_json("/__jc/api/git/diff?file=_posts/2026-10-17-draft.md")
    assert_includes d["diff"], "+title: Draft"

    build = @h.get_json("/__jc/api/state")[1]["build_id"]
    code, res = @h.post_json("/__jc/api/git/discard", file: "_data/i18n/it.yml")
    assert_equal [200, true], [code, res["ok"]]
    assert_includes @h.read("_data/i18n/it.yml"), "subtitle: 'Parlaci oggi'"
    assert_operator @h.get_json("/__jc/api/state")[1]["build_id"], :>, build
    assert_includes @h.get("/it/", token: false).body, "Parlaci oggi"

    @h.post_json("/__jc/api/git/discard", file: "_posts/2026-10-17-draft.md")
    refute File.exist?(@h.path("_posts/2026-10-17-draft.md"))

    @h.edit(op: "yaml", file: "_data/i18n/it.yml", keypath: %w[home hero subtitle], old: "Parlaci oggi", new: "Scrivici")
    code, res = @h.post_json("/__jc/api/git/commit", message: "Edit subtitle", files: ["_data/i18n/it.yml"])
    assert_equal 200, code, res.inspect
    assert_match(/\A[0-9a-f]{7,}\z/, res["sha"])
    assert_equal "Edit subtitle", @h.git("log", "-1", "--format=%s").strip
    assert_equal "Test User", @h.git("log", "-1", "--format=%an").strip
    assert_equal [], @h.get_json("/__jc/api/git/status")[1]["files"]
    code, res = @h.post_json("/__jc/api/git/commit", message: "Nothing")
    assert_equal [500, "git_failed"], [code, res["code"]]
  end

  def test_git_status_without_repo
    FileUtils.rm_rf(@h.path(".git"))
    # a temp dir outside any repository: git reports "not a work tree"
    _, st = @h.get_json("/__jc/api/git/status")
    assert_equal false, st["git"]
  end

  # --- invariants ----------------------------------------------------------------------------------------------

  def test_site_folder_untouched_by_builds
    assert_equal @before, @h.listing, "a build must not create files in the site folder"
    assert_empty @h.git("status", "--porcelain").lines
    @h.builder.build
    @h.get_json("/__jc/api/site")
    @h.page("/")
    assert_equal @before, @h.listing
    assert_empty @h.git("status", "--porcelain").lines
    assert Dir.exist?(File.join(@h.cache, "site"))
    refute Dir.exist?(File.join(@h.cache, "site.next"))
  end

  def test_edits_only_touch_the_edited_file
    @h.edit(op: "yaml", file: "_data/i18n/en.yml", keypath: %w[site name], old: "Fixture Co", new: "Fixture Company")
    assert_equal ["M _data/i18n/en.yml"], @h.git("status", "--porcelain").lines.map(&:strip)
    assert_equal @before, @h.listing
  end

  def test_watcher_rebuilds_on_external_change_but_not_on_own_writes
    @h.watcher.snapshot!
    @h.edit(op: "yaml", file: "_data/i18n/en.yml", keypath: %w[site name], old: "Fixture Co", new: "Fixture Company")
    assert_equal 2, @h.builder.build_id
    refute @h.watcher.tick, "own writes are ignored"
    sleep 0.02
    @h.write("_data/i18n/en.yml", @h.read("_data/i18n/en.yml").sub("Fixture Company", "Edited Outside"))
    assert @h.watcher.tick, "external change triggers a rebuild"
    assert_equal 3, @h.builder.build_id
    assert_includes @h.get("/", token: false).body, "Edited Outside"
    refute @h.watcher.tick
  end
end

class WithoutPolyglotTest < Minitest::Test
  def test_site_without_polyglot_builds_and_traces
    root = File.expand_path("fixtures/plain_site", __dir__)
    probe = File.expand_path("support/probe_plain.rb", __dir__)
    out, err, status = Open3.capture3(RbConfig.ruby, probe, root)
    assert status.success?, err
    data = JSON.parse(out.lines.last)
    assert data["ok"], data["error"]
    assert_equal ["en"], data["languages"]
    assert_equal ["/", "/2026/01/01/first.html"], data["records"].map { |r| r["url"] }.sort
    assert_equal [["hello"]], data["records"].find { |r| r["url"] == "/" }["strings"]
    assert_includes data["html"], '<p data-jc-line="5">Intro paragraph.</p>'
    assert_includes data["html"], '<h2 id="heading" data-jc-line="7">Heading</h2>'
  end
end
