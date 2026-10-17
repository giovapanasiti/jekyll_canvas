# frozen_string_literal: true

require "fileutils"
require "yaml"
require_relative "errors"

module JekyllCanvas
  # Image listing and upload.
  class Media
    EXTENSIONS = %w[.png .jpg .jpeg .webp .gif .svg .avif].freeze
    SKIP_DIRS = %w[_site node_modules vendor].freeze
    DEFAULT_UPLOADS = "assets/img/uploads"

    def initialize(root:, info:, extra_skip: [])
      @root = File.realpath(root)
      @info = info
      @extra_skip = extra_skip.map { |p| File.expand_path(p) }
    end

    def uploads_dir
      config = File.join(@root, ".jekyll-canvas.yml")
      value = File.file?(config) ? (YAML.safe_load_file(config) || {})["uploads_dir"] : nil
      value.is_a?(String) && !value.strip.empty? ? value.strip.sub(%r{\A/+}, "").chomp("/") : DEFAULT_UPLOADS
    rescue StandardError
      DEFAULT_UPLOADS
    end

    def list
      files = []
      walk(@root) do |path|
        next unless EXTENSIONS.include?(File.extname(path).downcase)

        stat = File.stat(path)
        rel = path.delete_prefix("#{@root}/")
        files << { src: "#{@info[:baseurl]}/#{rel}", file: rel, name: File.basename(path), size: stat.size, mtime: stat.mtime.to_i }
      end
      { uploads_dir: uploads_dir, data: files.sort_by { |f| -f[:mtime] } }
    end

    # Saves bytes under the uploads dir; returns the site-relative file path.
    def save(original_name, bytes)
      original_name = original_name.to_s.dup.force_encoding("UTF-8").scrub
      ext = File.extname(original_name.to_s).downcase
      raise ApiError.new("invalid", "unsupported image type #{ext.inspect}") unless EXTENSIONS.include?(ext)

      dir = uploads_dir
      FileUtils.mkdir_p(File.join(@root, dir))
      base = self.class.sanitize(File.basename(original_name.to_s, ".*"))
      name = "#{base}#{ext}"
      n = 1
      while File.exist?(File.join(@root, dir, name))
        n += 1
        name = "#{base}-#{n}#{ext}"
      end
      File.binwrite(File.join(@root, dir, name), bytes)
      File.join(dir, name)
    end

    def self.sanitize(name)
      ascii = name.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      ascii.empty? ? "image" : ascii
    end

    private

    def excluded?(rel)
      Array(@info[:exclude]).any? do |entry|
        entry = entry.to_s.chomp("/")
        rel == entry || rel.start_with?("#{entry}/") || File.fnmatch?(entry, rel, File::FNM_PATHNAME | File::FNM_EXTGLOB)
      end
    end

    def walk(dir, &block)
      Dir.children(dir).each do |name|
        next if name.start_with?(".") || SKIP_DIRS.include?(name)

        path = File.join(dir, name)
        rel = path.delete_prefix("#{@root}/")
        next if excluded?(rel) || @extra_skip.include?(path)

        stat = File.lstat(path)
        if stat.directory? then walk(path, &block)
        elsif stat.file? then yield path
        end
      end
    rescue SystemCallError
      nil
    end
  end
end
