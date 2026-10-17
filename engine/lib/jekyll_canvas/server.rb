# frozen_string_literal: true

require "webrick"
require "json"
require "securerandom"
require "uri"
require_relative "errors"
require_relative "edits"
require_relative "git"
require_relative "locator"
require_relative "media"
require_relative "new_document"
require_relative "page_api"
require_relative "paths"

module JekyllCanvas
  # WEBrick server: editor UI at /__jc/, JSON API at /__jc/api/, the built site everywhere else.
  class Server
    UI_PREFIX = "/__jc"
    API_PREFIX = "/__jc/api/"

    attr_reader :token, :port

    def initialize(root:, builder:, watcher:, public_dir:, port: 0)
      @root = File.realpath(root)
      @builder = builder
      @watcher = watcher
      @public_dir = public_dir
      @token = SecureRandom.hex(16)
      @edits = Edits.new(root: @root, builder: builder, watcher: watcher)
      @pages = PageApi.new(root: @root, builder: builder)
      @git = Git.new(@root)
      @http = WEBrick::HTTPServer.new(
        BindAddress: "127.0.0.1", Port: port, AccessLog: [],
        Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN)
      )
      @port = @http.config[:Port]
      @http.mount_proc("/") { |req, res| dispatch(req, res) }
    end

    def url
      "http://127.0.0.1:#{@port}/__jc/?token=#{@token}"
    end

    def start
      @http.start
    end

    def start_in_background
      @thread = Thread.new { @http.start }
    end

    def shutdown
      @http.shutdown
    end

    private

    def dispatch(req, res)
      res["Cache-Control"] = "no-store"
      path = req.path.to_s
      if path.start_with?(API_PREFIX)
        api(req, res, path.delete_prefix(API_PREFIX))
      elsif path == UI_PREFIX
        res.set_redirect(WEBrick::HTTPStatus::MovedPermanently, "#{UI_PREFIX}/#{req.query_string ? "?#{req.query_string}" : ''}")
      elsif path.start_with?("#{UI_PREFIX}/")
        serve_file(res, @public_dir, path.delete_prefix("#{UI_PREFIX}/"), index: true)
      else
        serve_site(req, res, path)
      end
    end

    # --- static ---------------------------------------------------------------------------------

    def serve_file(res, base, rel, index: false)
      rel = URI.decode_www_form_component(rel.to_s.gsub("+", "%2B"))
      rel = "index.html" if rel.empty? && index
      abs = safe_join(base, rel)
      abs = File.join(abs, "index.html") if abs && File.directory?(abs)
      return not_found(res) unless abs && File.file?(abs)

      send_file(res, abs)
    end

    def serve_site(req, res, path)
      base = @builder.dest
      rel = URI.decode_www_form_component(path.delete_prefix("/").gsub("+", "%2B"))
      abs = safe_join(base, rel)
      return not_found(res, status: 404, site: true) unless abs

      if File.directory?(abs)
        unless path.end_with?("/")
          return res.set_redirect(WEBrick::HTTPStatus::MovedPermanently, "#{path}/#{req.query_string ? "?#{req.query_string}" : ''}")
        end

        abs = File.join(abs, "index.html")
      elsif !File.file?(abs)
        abs = File.file?("#{abs}.html") ? "#{abs}.html" : nil
      end
      return not_found(res, site: true) unless abs && File.file?(abs)

      send_file(res, abs)
    end

    def safe_join(base, rel)
      return nil if rel.include?("\0")

      abs = File.expand_path(rel, base)
      Paths.inside?(File.expand_path(base), abs) ? abs : nil
    end

    def send_file(res, abs, status: 200)
      res.status = status
      res["Content-Type"] = WEBrick::HTTPUtils.mime_type(abs, WEBrick::HTTPUtils::DefaultMimeTypes)
      res["Content-Type"] = "#{res['Content-Type']}; charset=utf-8" if res["Content-Type"].start_with?("text/", "application/javascript")
      res.body = File.binread(abs)
    end

    def not_found(res, status: 404, site: false)
      page = site ? File.join(@builder.dest, "404.html") : nil
      if page && File.file?(page)
        send_file(res, page, status: status)
      else
        res.status = status
        res["Content-Type"] = "text/plain; charset=utf-8"
        res.body = "Not found"
      end
    end

    # --- API --------------------------------------------------------------------------------------

    def api(req, res, route)
      unless authorized?(req)
        return json(res, { ok: false, error: "forbidden", code: "forbidden" }, 403)
      end

      result = route_request(req, route)
      json(res, result)
    rescue ApiError => e
      json(res, { ok: false, error: e.message, code: e.code }.merge(e.extra), e.status)
    rescue JSON::ParserError => e
      json(res, { ok: false, error: "invalid JSON: #{e.message}", code: "invalid" }, 422)
    rescue StandardError => e
      warn "[jekyll-canvas] #{req.request_method} #{req.path}: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      json(res, { ok: false, error: "#{e.class}: #{e.message}", code: "internal" }, 500)
    end

    def authorized?(req)
      given = req["x-jc-token"].to_s
      given.bytesize == @token.bytesize && given.bytes.zip(@token.bytes).sum { |a, b| a ^ b }.zero?
    end

    def json(res, body, status = 200)
      res.status = status
      res["Content-Type"] = "application/json; charset=utf-8"
      res.body = JSON.generate(body)
    end

    def body_json(req)
      raw = req.body.to_s
      raw.strip.empty? ? {} : JSON.parse(raw)
    end

    def route_request(req, route)
      verb = req.request_method
      case [verb, route]
      when ["GET", "state"] then @builder.state
      when ["POST", "rebuild"] then rebuild
      when ["GET", "site"] then @pages.site
      when ["GET", "page"] then @pages.page(query(req, "url"))
      when ["GET", "md-block"] then @pages.md_block(query(req, "file"), query(req, "line"))
      when ["POST", "locate"] then locate(body_json(req))
      when ["POST", "edit"] then @edits.apply(body_json(req))
      when ["POST", "new"] then new_document(body_json(req))
      when ["GET", "file"] then @pages.file(query(req, "file"))
      when ["GET", "media"] then media.list
      when ["POST", "media"] then upload(req)
      when ["GET", "git/status"] then @git.status
      when ["GET", "git/diff"] then git_diff(query(req, "file"))
      when ["POST", "git/discard"] then git_discard(body_json(req))
      when ["POST", "git/commit"] then git_commit(body_json(req))
      else raise ApiError.new("not_found", "unknown endpoint #{verb} #{route}")
      end
    end

    def query(req, name)
      value = req.query[name]
      raise ApiError.new("invalid", "missing #{name}") if value.nil? || value.to_s.empty?

      value.to_s
    end

    def resolve(file)
      Paths.resolve(@root, file, cache_dir: @builder.cache_dir)
    rescue Paths::Invalid => e
      raise ApiError.new("forbidden", e.message)
    end

    def media
      Media.new(root: @root, info: @builder.info, extra_skip: [@builder.cache_dir])
    end

    def rebuild
      @builder.synchronize { @builder.build }
      @builder.state.merge(ok: true)
    end

    def locate(params)
      url = Paths.normalize_url(params["url"])
      text = params["text"].to_s
      record = @builder.records[url] or raise ApiError.new("not_found", "no page rendered at #{url}")
      { candidates: Locator.new(@root).locate(record, text) }
    end

    def new_document(params)
      @builder.synchronize do
        creator = NewDocument.new(root: @root, records: @builder.records, info: @builder.info)
        rel = creator.create(collection: params["collection"].to_s, lang: params["lang"].to_s, title: params["title"],
                             slug: params["slug"], date: params["date"])
        @watcher&.acknowledge(File.join(@root, rel))
        @builder.build
        record = @builder.records.find { |r| r.file == rel && r.lang == params["lang"].to_s } ||
                 @builder.records.find { |r| r.file == rel }
        { ok: true, file: rel, url: record&.url, build_id: @builder.build_id, error: @builder.error }
      end
    end

    def upload(req)
      form = req.query["file"]
      raise ApiError.new("invalid", "missing file field") if form.nil? || form.to_s.empty?

      name = form.respond_to?(:filename) ? form.filename.to_s : "upload"
      @builder.synchronize do
        rel = media.save(name, form.to_s)
        @watcher&.acknowledge(File.join(@root, rel))
        @builder.build
        { ok: true, src: "#{@builder.info[:baseurl]}/#{rel}", file: rel }
      end
    end

    def git_diff(file)
      resolve(file)
      { diff: @git.diff(file) }
    end

    def git_discard(params)
      file = params["file"].to_s
      abs = resolve(file)
      @builder.synchronize do
        @watcher&.ignore(abs)
        @git.discard(file, abs)
        @watcher&.acknowledge(abs)
        @builder.build
      end
      { ok: true }
    end

    def git_commit(params)
      files = params["files"]
      files = Array(files).map(&:to_s) if files
      files&.each { |f| resolve(f) }
      sha = @builder.synchronize { @git.commit(params["message"], files) }
      { ok: true, sha: sha }
    end
  end
end
