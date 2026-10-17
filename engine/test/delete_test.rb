# frozen_string_literal: true

require "support/harness"

class DeleteTest < Minitest::Test
  POST = "_posts/2026-01-10-hello-world.md"

  def setup
    @h = Harness.new
    @h.build!
  end

  def teardown
    @h.close
  end

  def site_files
    _, site = @h.get_json("/__jc/api/site")
    site["groups"].flat_map { |g| g["items"].map { |i| i["file"] } }
  end

  def test_delete_post_moves_it_to_the_trash_and_rebuilds
    assert_includes site_files, POST
    original = @h.read(POST)
    build = @h.builder.build_id
    code, res = @h.post_json("/__jc/api/delete", file: POST)
    assert_equal 200, code, res.inspect
    assert_equal [true, nil], [res["ok"], res["error"]]
    assert_equal File.join(@h.trash_dir, "2026-01-10-hello-world.md"), res["trashed_to"]
    assert_operator res["build_id"], :>, build
    assert res["build_ms"]
    refute File.exist?(@h.path(POST))
    assert_equal original, File.read(res["trashed_to"], encoding: "UTF-8")
    refute_includes site_files, POST
    assert_equal "D", @h.get_json("/__jc/api/git/status")[1]["files"].find { |f| f["path"] == POST }["status"]
    assert_equal 404, @h.get("/blog/hello-world/", token: false).code.to_i
  end

  def test_delete_a_collection_document
    code, res = @h.post_json("/__jc/api/delete", file: "_projects/alpha.md")
    assert_equal 200, code, res.inspect
    refute File.exist?(@h.path("_projects/alpha.md"))
    assert File.exist?(res["trashed_to"])
  end

  def test_delete_restores_via_git_discard
    @h.post_json("/__jc/api/delete", file: POST)
    @h.post_json("/__jc/api/git/discard", file: POST)
    assert File.exist?(@h.path(POST))
    assert_includes site_files, POST
  end

  def test_pages_and_other_files_are_refused
    ["about.html", "_layouts/post.html", "_data/nav.yml", "index.html"].each do |file|
      code, res = @h.post_json("/__jc/api/delete", file: file)
      assert_equal [422, "invalid"], [code, res["code"]], file
      assert_includes res["error"], "solo articoli"
      assert File.exist?(@h.path(file)), file
    end
    assert_empty Dir.glob("#{@h.trash_dir}/*")
  end

  def test_missing_outside_and_unauthorized
    code, res = @h.post_json("/__jc/api/delete", file: "_posts/2000-01-01-nope.md")
    assert_equal [404, "not_found"], [code, res["code"]]
    code, res = @h.post_json("/__jc/api/delete", file: "../x.md")
    assert_equal [403, "forbidden"], [code, res["code"]]
    code, res = @h.post_json("/__jc/api/delete", file: ".git/config")
    assert_equal [403, "forbidden"], [code, res["code"]]
    code, = @h.post_json("/__jc/api/delete", { file: POST }, token: false)
    assert_equal 403, code
    assert File.exist?(@h.path(POST))
  end

  def test_watcher_does_not_rebuild_after_a_delete
    @h.watcher.snapshot!
    @h.post_json("/__jc/api/delete", file: POST)
    refute @h.watcher.tick
  end
end

class TrashTest < Minitest::Test
  def setup
    @tmp = Dir.mktmpdir("jc-trash")
    @src = File.join(@tmp, "my site", "_posts")
    FileUtils.mkdir_p(@src)
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def source(name = "2026-10-17-é post.md", content = "hello")
    path = File.join(@src, name)
    File.write(path, content)
    path
  end

  def test_freedesktop_writes_trashinfo_and_moves_the_file
    data = File.join(@tmp, "xdg")
    now = Time.new(2026, 10, 17, 9, 5, 3)
    trash = JekyllCanvas::Trash.new(platform: "x86_64-linux", xdg_data_home: data, gio: false, clock: -> { now })
    path = source
    target = trash.trash(path)
    assert_equal File.join(data, "Trash", "files", "2026-10-17-é post.md"), target
    refute File.exist?(path)
    assert_equal "hello", File.read(target)
    info = File.binread(File.join(data, "Trash", "info", "2026-10-17-é post.md.trashinfo")).force_encoding("UTF-8")
    encoded = "#{@tmp}/my%20site/_posts/2026-10-17-%C3%A9%20post.md"
    assert_equal "[Trash Info]\nPath=#{encoded}\nDeletionDate=2026-10-17T09:05:03\n", info
  end

  def test_freedesktop_unique_names
    data = File.join(@tmp, "xdg")
    trash = JekyllCanvas::Trash.new(platform: "x86_64-linux", xdg_data_home: data, gio: false)
    a = trash.trash(source("a.md", "1"))
    b = trash.trash(source("a.md", "2"))
    assert_equal ["a.md", "a.1.md"], [File.basename(a), File.basename(b)]
    assert_equal %w[a.1.md.trashinfo a.md.trashinfo], Dir.children(File.join(data, "Trash", "info")).sort
    assert_equal "1", File.read(a)
    assert_equal "2", File.read(b)
  end

  def test_mac_collision_gets_a_unique_name
    dir = File.join(@tmp, ".Trash")
    now = Time.new(2026, 10, 17, 9, 5, 3)
    trash = JekyllCanvas::Trash.new(platform: "arm64-darwin24", mac_trash: dir, clock: -> { now })
    first = trash.trash(source("a.md", "1"))
    second = trash.trash(source("a.md", "2"))
    third = trash.trash(source("a.md", "3"))
    assert_equal File.join(dir, "a.md"), first
    assert_equal File.join(dir, "a 09.05.03.md"), second
    assert_equal File.join(dir, "a 09.05.03-2.md"), third
    assert_equal %w[1 2 3], [first, second, third].map { |f| File.read(f) }
  end

  def test_failure_raises_and_never_deletes
    blocker = File.join(@tmp, "blocker")
    File.write(blocker, "x")
    trash = JekyllCanvas::Trash.new(platform: "arm64-darwin", mac_trash: File.join(blocker, "Trash"))
    path = source
    err = assert_raises(JekyllCanvas::ApiError) { trash.trash(path) }
    assert_equal "invalid", err.code
    assert File.exist?(path)
  end
end
