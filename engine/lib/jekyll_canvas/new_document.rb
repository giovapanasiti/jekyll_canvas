# frozen_string_literal: true

require "date"
require "fileutils"
require_relative "errors"
require_relative "front_matter"
require_relative "yaml_editor"

module JekyllCanvas
  # Creates a post / collection item shaped like its newest sibling in the same language.
  class NewDocument
    BODY = "\nScrivi qui il testo.\n"

    def initialize(root:, records:, info:)
      @root = root
      @records = records
      @info = info
    end

    def self.slugify(text)
      text.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
    end

    # Returns the site-relative path of the created file.
    def create(collection:, lang:, title:, slug: nil, date: nil)
      title = title.to_s.strip
      raise ApiError.new("invalid", "title is required") if title.empty?

      slug = self.class.slugify(slug.to_s.empty? ? title : slug)
      raise ApiError.new("invalid", "could not derive a slug") if slug.empty?

      date = (date.to_s.empty? ? Date.today.iso8601 : date.to_s)
      raise ApiError.new("invalid", "date must be YYYY-MM-DD") unless date.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      posts = collection == "posts"
      template = template_record(collection, lang)
      dir = template ? File.dirname(template.file) : default_dir(collection)
      name = posts ? "#{date}-#{slug}.md" : "#{slug}.md"
      rel = dir == "." ? name : File.join(dir, name)
      path = File.join(@root, rel)
      raise ApiError.new("conflict", "#{rel} already exists") if File.exist?(path)

      template_data = template ? template_front_matter(template) : nil
      pairs = front_matter_pairs(template_data, template&.file, title: title, lang: lang, slug: slug, date: date, posts: posts)
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o644) do |f|
        f.write("---\n#{render_pairs(pairs)}---\n#{BODY}")
      end
      rel
    rescue Errno::EEXIST
      raise ApiError.new("conflict", "#{rel} already exists")
    end

    private

    def template_record(collection, lang)
      candidates = @records.select { |r| r.collection == collection && r.kind == "document" }
                           .uniq(&:file)
      same_lang = candidates.select { |r| (r.doc_lang || r.lang) == lang }
      pool = same_lang.empty? ? candidates : same_lang
      pool.max_by { |r| r.date ? r.date.to_time.to_f : mtime(r.file) }
    end

    def mtime(file)
      File.mtime(File.join(@root, file)).to_f
    rescue SystemCallError
      0.0
    end

    def default_dir(collection)
      base = @info[:collections_dir].to_s
      folder = collection == "posts" ? "_posts" : "_#{collection}"
      base.empty? ? folder : File.join(base, folder)
    end

    def template_front_matter(record)
      content = File.binread(File.join(@root, record.file)).force_encoding("UTF-8").scrub
      FrontMatter.load_hash(FrontMatter.split(content).raw)
    end

    def front_matter_pairs(template, template_file, title:, lang:, slug:, date:, posts:)
      multilingual = @info[:languages].to_a.length > 1
      if template.nil?
        pairs = [["title", title]]
        pairs << ["lang", lang] if multilingual
        pairs << ["date", Date.iso8601(date)] if posts
        return pairs
      end

      pairs = template.filter_map do |key, value|
        case key.to_s
        when "title" then [key, title]
        when "lang" then [key, lang]
        when "date" then [key, Date.iso8601(date)]
        when "layout" then [key, value]
        when "lang-exclusive" then [key, [lang]]
        when "page_id" then [key, slug]
        when "permalink"
          permalink = derive_permalink(value, template_file, slug)
          permalink ? [key, permalink] : nil
        else [key, blank(value, 0)]
        end
      end
      pairs << ["date", Date.iso8601(date)] if posts && pairs.none? { |k, _| k.to_s == "date" }
      pairs
    end

    # Replaces the last path segment of the template's permalink with the new slug
    # (a blank permalink would make Jekyll emit a broken URL).
    def derive_permalink(value, template_file, slug)
      return nil unless value.is_a?(String) && value.start_with?("/")

      trailing = value.end_with?("/")
      segments = value.split("/")
      return nil if segments.length < 2

      segments[-1] = slug
      segments.join("/") + (trailing ? "/" : "")
    end

    def blank(value, depth)
      case value
      when String then ""
      when true, false then false
      when Array then []
      when Hash then depth.zero? ? value.transform_values { |v| blank(v, depth + 1) } : {}
      end
    end

    def render_pairs(pairs)
      pairs.map { |k, v| render_entry(k.to_s, v, 0) }.join
    end

    def render_entry(key, value, indent)
      pad = " " * indent
      rendered_key = YamlEditor.plain_ok?(key) ? key : YamlEditor.double_quote(key)
      if value.is_a?(Hash) && !value.empty?
        "#{pad}#{rendered_key}:\n" + value.map { |k, v| render_entry(k.to_s, v, indent + 2) }.join
      else
        text = render_value(value)
        "#{pad}#{rendered_key}:#{text.empty? ? '' : " #{text}"}\n"
      end
    end

    def render_value(value)
      case value
      when nil then ""
      when Hash then "{}"
      when Array then "[#{value.map { |v| render_value(v) }.join(', ')}]"
      when Date then value.iso8601
      when String then YamlEditor.plain_ok?(value, true) ? value : YamlEditor.double_quote(value)
      else YamlEditor.literal_scalar(value)
      end
    end
  end
end
