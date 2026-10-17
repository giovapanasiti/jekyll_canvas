# frozen_string_literal: true

require "monitor"
require "fileutils"
require "jekyll"
require_relative "tracer"
require_relative "records"

module JekyllCanvas
  # Builds the site in-process into the cache directory and keeps the latest good result.
  # One reentrant lock serialises builds and edits.
  class Builder
    OVERRIDES = {
      "disable_disk_cache" => true, "incremental" => false, "watch" => false, "livereload" => false,
      "parallel_localization" => false, "quiet" => true, "show_drafts" => false, "profile" => false
    }.freeze

    attr_reader :root, :cache_dir, :records, :info, :build_id, :error, :last_build_ms

    def initialize(root:, cache_dir:)
      @root = File.realpath(root)
      @cache_dir = File.expand_path(cache_dir)
      @monitor = Monitor.new
      @records = Records.new
      @info = { languages: ["en"], default_lang: "en", collections: {}, kramdown: { "input" => "GFM" }, exclude: [], include: [] }
      @build_id = 0
      @building = false
      @error = nil
      @last_build_ms = 0
      FileUtils.mkdir_p(@cache_dir)
      FileUtils.rm_rf([next_dest, prev_dest])
      Jekyll.logger.log_level = :warn
    end

    def dest = File.join(@cache_dir, "site")
    def next_dest = File.join(@cache_dir, "site.next")
    def prev_dest = File.join(@cache_dir, "site.prev")

    def synchronize(&block)
      @monitor.synchronize(&block)
    end

    def state
      { build_id: @build_id, building: @building, error: @error, last_build_ms: @last_build_ms }
    end

    # Runs a full build. Returns true on success; on failure the previous build keeps being served.
    def build
      synchronize do
        @building = true
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        records = Records.new
        site = nil
        begin
          FileUtils.rm_rf(next_dest)
          Tracer.begin_session(records)
          site = Jekyll::Site.new(Jekyll.configuration(overrides))
          site.process
          languages = Tracer.languages_of(site)
          records.finalize!(languages)
          publish(site, records, languages)
          @error = nil
          @build_id += 1
          true
        rescue StandardError, SystemExit => e
          FileUtils.rm_rf(next_dest)
          @error = describe(e)
          warn "[jekyll-canvas] build failed: #{@error}"
          false
        ensure
          Tracer.end_session
          Jekyll.sites.delete(site) if site
          @last_build_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
          @building = false
        end
      end
    end

    private

    def overrides
      OVERRIDES.merge("source" => @root, "destination" => next_dest)
    end

    def publish(site, records, languages)
      FileUtils.rm_rf(prev_dest)
      File.rename(dest, prev_dest) if File.exist?(dest)
      File.rename(next_dest, dest)
      FileUtils.rm_rf(prev_dest)
      @records = records
      @info = {
        title: site.config["title"], languages: languages, default_lang: Tracer.default_lang_of(site),
        collections: site.collections.transform_values { |c| { output: c.write?, label: c.label } },
        kramdown: site.config["kramdown"] || {}, exclude: Array(site.config["exclude"]),
        include: Array(site.config["include"]), baseurl: site.config["baseurl"].to_s,
        markdown_ext: site.config["markdown_ext"].to_s, collections_dir: site.config["collections_dir"].to_s
      }
    end

    def describe(error)
      return "build aborted" if error.is_a?(SystemExit)

      message = error.message.to_s.strip
      message.include?(error.class.name.to_s) ? message : "#{error.class}: #{message}"
    end
  end
end
