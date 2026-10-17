# frozen_string_literal: true

require_relative "errors"
require_relative "front_matter"
require_relative "git"
require_relative "markdown_blocks"
require_relative "paths"
require_relative "siblings"

module JekyllCanvas
  # Read-only JSON documents for /site, /page, /md-block and /file.
  class PageApi
    def initialize(root:, builder:)
      @root = root
      @builder = builder
    end

    def site
      info = @builder.info
      records = @builder.records
      {
        root: @root, name: File.basename(@root), title: info[:title] || File.basename(@root),
        languages: info[:languages], default_lang: info[:default_lang],
        git: Git.new(@root).repo?, groups: groups(records, info)
      }
    end

    def page(url)
      url = Paths.normalize_url(url)
      record = @builder.records[url] or raise ApiError.new("not_found", "no page rendered at #{url}")
      abs = File.join(@root, record.file)
      raise ApiError.new("not_found", "source file is gone: #{record.file}") unless File.file?(abs)

      parts = FrontMatter.split(read(abs))
      languages = @builder.info[:languages]
      siblings = Siblings.new(root: @root, languages: languages, records: @builder.records)
      strings = record.strings.values.each_with_index.map do |s, i|
        { id: "s#{i + 1}", value: s[:value], file: s[:file], keypath: s[:keypath], source: s[:source],
          editable: editable?(s), siblings: siblings.for(s) }
      end
      {
        url: record.url, lang: record.lang, file: record.file, kind: record.kind, collection: record.collection,
        format: record.format, title: record.title || Paths.humanize(File.basename(record.file, ".*")),
        front_matter: parts.front_matter? ? { raw: parts.raw, data: FrontMatter.load_hash(parts.raw) } : nil,
        body_start_line: parts.body_start_line, body: parts.body, strings: strings,
        layouts: record.layouts, includes: record.includes,
        translations: record.translations
      }
    end

    def md_block(file, line)
      abs = resolve(file)
      raise ApiError.new("not_found", "file not found") unless File.file?(abs)

      line = Integer(line.to_s, exception: false) or raise ApiError.new("invalid", "line must be an integer")
      content = read(abs)
      parts = FrontMatter.split(content)
      rel_line = line - parts.body_start_line + 1
      block = rel_line >= 1 ? MarkdownBlocks.block_at(parts.body, rel_line, @builder.info[:kramdown]) : nil
      raise ApiError.new("not_found", "no Markdown block at line #{line}") unless block

      start_line = block.start_line + parts.body_start_line - 1
      end_line = block.end_line + parts.body_start_line - 1
      markdown = content.lines[(start_line - 1)...end_line].join.chomp.gsub("\r\n", "\n")
      { file: file, start_line: start_line, end_line: end_line, type: block.type.to_s,
        header_level: block.header_level, markdown: markdown }
    end

    def file(file)
      abs = resolve(file)
      raise ApiError.new("not_found", "file not found") unless File.file?(abs)

      { file: file, content: read(abs) }
    end

    private

    def resolve(file)
      Paths.resolve(@root, file, cache_dir: @builder.cache_dir)
    rescue Paths::Invalid => e
      raise ApiError.new("forbidden", e.message)
    end

    def read(abs)
      File.binread(abs).force_encoding("UTF-8").scrub
    end

    def editable?(string)
      return true if string[:source] == "front_matter"

      %w[.yml .yaml].include?(File.extname(string[:file]).downcase)
    end

    def groups(records, info)
      list = []
      pages = records.select { |r| r.kind == "page" && r.html && !r.redirect }.sort_by(&:url)
      list << { id: "pages", label: "Pagine", collection: nil, can_create: false, items: pages.map { |r| item(r) } }

      labels = info[:collections].select { |_, c| c[:output] }.keys
      labels = (["posts"] & labels) + (labels - ["posts"])
      labels.each do |label|
        docs = records.select { |r| r.collection == label && r.html }
        docs = label == "posts" ? docs.sort_by { |r| [-(r.date&.to_f || 0), r.url] } : docs.sort_by { |r| [r.order.is_a?(Numeric) ? r.order : Float::INFINITY, r.title.to_s.downcase, r.url] }
        list << { id: label, label: label == "posts" ? "Articoli" : Paths.humanize(label), collection: label,
                  can_create: true, items: docs.map { |r| item(r) } }
      end
      list
    end

    def item(record)
      { file: record.file, title: record.title || Paths.humanize(File.basename(record.file, ".*")),
        lang: record.lang, url: record.url }
    end
  end
end
