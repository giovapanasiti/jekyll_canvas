# frozen_string_literal: true

require "test_helper"
require "net/http"
require "open3"
require "jekyll_canvas"

# Copies the fixture site to a temp dir (with git), builds it and serves the API on a random port.
class Harness
  FIXTURE = File.expand_path("../fixtures/site", __dir__)

  attr_reader :root, :cache, :builder, :server, :watcher, :trash_dir

  # The server trashes into a temp dir (macOS layout) so tests never touch the real Trash.
  def initialize
    @tmp = Dir.mktmpdir("jc-test")
    @trash_dir = File.join(@tmp, "trash")
    @root = File.join(@tmp, "site")
    @cache = File.join(@tmp, "cache")
    FileUtils.cp_r(FIXTURE, @root)
    git("init", "-q")
    git("config", "user.name", "Test User")
    git("config", "user.email", "test@example.test")
    git("add", "-A")
    git("commit", "-qm", "initial")
    @builder = JekyllCanvas::Builder.new(root: @root, cache_dir: @cache)
    @watcher = JekyllCanvas::Watcher.new(root: @root, builder: @builder)
    public_dir = File.expand_path("../../public", __dir__)
    @server = JekyllCanvas::Server.new(root: @root, builder: @builder, watcher: @watcher, public_dir: public_dir, port: 0,
                                         trash: JekyllCanvas::Trash.new(platform: "arm64-darwin", mac_trash: @trash_dir))
    @server.start_in_background
  end

  def build!
    @builder.build || raise("build failed: #{@builder.error}")
  end

  def close
    @server.shutdown
    @watcher.stop
    FileUtils.remove_entry(@tmp)
  end

  def git(*args)
    out, status = Open3.capture2e("git", "-C", @root, *args)
    raise "git #{args.join(' ')} failed: #{out}" unless status.success?

    out
  end

  def path(rel) = File.join(@root, rel)
  def read(rel) = File.read(path(rel), encoding: "UTF-8")
  def write(rel, content) = File.write(path(rel), content)

  def listing
    Dir.glob("**/*", File::FNM_DOTMATCH, base: @root).reject { |f| f.start_with?(".git/") || f == ".git" || f == "." }.sort
  end

  # --- HTTP ---------------------------------------------------------------------------------------

  def http(request, token: true)
    request["X-JC-Token"] = @server.token if token
    Net::HTTP.start("127.0.0.1", @server.port) { |h| h.request(request) }
  end

  def get(path, token: true)
    http(Net::HTTP::Get.new(path), token: token)
  end

  def get_json(path)
    res = get(path)
    [res.code.to_i, JSON.parse(res.body)]
  end

  def post_json(path, body = nil, **opts)
    token = opts.fetch(:token, true)
    body ||= opts.except(:token)
    req = Net::HTTP::Post.new(path, "Content-Type" => "application/json")
    req.body = JSON.generate(body)
    res = http(req, token: token)
    [res.code.to_i, JSON.parse(res.body)]
  end

  def upload(path, filename, bytes, content_type = "image/png")
    boundary = "----jctest#{rand(1_000_000)}"
    body = "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n" \
           "Content-Type: #{content_type}\r\n\r\n#{bytes}\r\n--#{boundary}--\r\n"
    req = Net::HTTP::Post.new(path, "Content-Type" => "multipart/form-data; boundary=#{boundary}")
    req.body = body.b
    res = http(req)
    [res.code.to_i, JSON.parse(res.body)]
  end

  def edit(op)
    post_json("/__jc/api/edit", op)
  end

  def page(url)
    get_json("/__jc/api/page?url=#{url}")
  end
end
