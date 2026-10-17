# frozen_string_literal: true

module JekyllCanvas
  # Path and URL helpers. Every `file` that crosses the API goes through `resolve`.
  module Paths
    class Invalid < StandardError; end

    module_function

    # "/it/servizi" -> "/it/servizi/", "/index.html" -> "/", "/a/index.html" -> "/a/".
    def normalize_url(url)
      path = url.to_s.split(/[?#]/).first.to_s
      path = "/#{path}" unless path.start_with?("/")
      path = path.squeeze("/").sub(%r{/index\.html\z}, "/")
      path += "/" unless path.end_with?("/") || File.extname(path) != ""
      path
    end

    # Absolute path for a site-relative `rel`, or raises Invalid when it escapes the root,
    # enters .git/ or the build cache.
    def resolve(root, rel, cache_dir: nil)
      rel = rel.to_s
      raise Invalid, "empty path" if rel.empty? || rel.include?("\0")
      raise Invalid, "absolute path" if rel.start_with?("/")

      real_root = File.realpath(root)
      abs = File.expand_path(rel, real_root)
      raise Invalid, "path outside the site" unless inside?(real_root, abs)

      segments = abs[(real_root.length + 1)..].to_s.split("/")
      raise Invalid, "path inside .git" if segments.include?(".git")

      if File.exist?(abs)
        real = File.realpath(abs)
        raise Invalid, "path outside the site" unless inside?(real_root, real)
      end
      if cache_dir
        real_cache = File.expand_path(cache_dir)
        raise Invalid, "path inside the build cache" if inside?(real_cache, abs) || abs == real_cache
      end
      abs
    end

    def inside?(base, path)
      path == base || path.start_with?(base.end_with?("/") ? base : "#{base}/")
    end

    def relative(root, abs)
      real_root = File.realpath(root)
      abs = File.expand_path(abs)
      abs = abs.sub(/\A#{Regexp.escape(root.to_s)}/, real_root) unless inside?(real_root, abs)
      abs[(real_root.length + 1)..]
    end

    LANGUAGES = {
      ".html" => "liquid-html", ".htm" => "liquid-html", ".liquid" => "liquid-html", ".xml" => "liquid-html",
      ".md" => "markdown", ".markdown" => "markdown", ".yml" => "yaml", ".yaml" => "yaml",
      ".scss" => "scss", ".sass" => "scss", ".css" => "scss", ".js" => "javascript", ".json" => "json"
    }.freeze

    # Editor language of a file, by extension (see spec-code-editor.md).
    def language(path)
      LANGUAGES.fetch(File.extname(path.to_s).downcase, "text")
    end

    # True when the first 8 KB of the file contain a NUL byte.
    def binary?(abs)
      File.binread(abs, 8192).to_s.include?("\0")
    end

    def humanize(name)
      name.to_s.tr("_-", "  ").strip.sub(/\A./) { |c| c.upcase }
    end
  end
end
