# frozen_string_literal: true

require "jekyll"
require "kramdown"
require_relative "front_matter"
require_relative "records"

module JekyllCanvas
  # Source tracing. While a build runs inside a Session, Jekyll/Liquid/kramdown are watched to
  # learn where each rendered piece of text comes from (see docs/design.md, "Source tracing").
  module Tracer
    EXCLUDED_FRONT_MATTER_KEYS = %w[layout lang page_id permalink lang-exclusive redirect_from published
                                    sitemap rendered_lang date].freeze
    DATA_GLOB = /\.(ya?ml|json|csv|tsv)\z/
    MAX_DEPTH = 40
    ANNOTATED_TYPES = %i[p header ul ol blockquote codeblock table hr html_element dl math].freeze

    Session = Struct.new(:records, :thread, :index, :target, :md_target, keyword_init: true)
    MdTarget = Struct.new(:body_start_line, keyword_init: true)

    class << self
      attr_reader :session

      def begin_session(records)
        @session = Session.new(records: records, thread: Thread.current, index: {}.compare_by_identity)
      end

      def end_session
        @session = nil
      end

      # The session, only when called from the building thread.
      def active
        s = @session
        s if s && s.thread.equal?(Thread.current)
      end

      def md_target
        active&.md_target
      end

      # --- Liquid lookups -------------------------------------------------------------

      def note(result)
        s = active or return
        target = s.target or return
        case result
        when String then note_string(s, target, result)
        when Array
          return if result.length > 500

          result.each { |v| note_string(s, target, v) if v.is_a?(String) }
        end
      end

      def note_string(session, target, string)
        entry = session.index[string] or return
        target.add_string(entry, string)
      end

      def note_include(tag, context)
        s = active or return
        target = s.target or return
        site = context.registers[:site]
        name = tag.render_variable(context) || tag.instance_variable_get(:@file)
        path = tag.tag_includes_dirs(context).map { |d| File.join(d.to_s, name.to_s) }.find { |p| File.file?(p) }
        rel = path && relative_to_source(site, path)
        target.add_include(rel) if rel
      rescue StandardError
        nil
      end

      def relative_to_source(site, abs)
        src = File.realpath(site.source)
        real = File.realpath(abs)
        real.delete_prefix("#{src}/") if real.start_with?("#{src}/")
      end

      # --- hooks ------------------------------------------------------------------------

      def on_post_read(site)
        s = active or return
        s.target = nil
        s.md_target = nil
        s.index = {}.compare_by_identity
        index_data(site, s.index)
        index_front_matter(site, s.index)
      rescue StandardError => e
        warn "[jekyll-canvas] tracing index failed: #{e.class}: #{e.message}"
      end

      def on_pre_render(doc)
        s = active or return
        s.target = nil
        return if doc.respond_to?(:write?) && !doc.write?

        abs = source_path(doc.site, doc)
        return unless abs && File.file?(abs)

        record = build_record(doc, abs)
        s.records.add(record)
        s.target = record
      rescue StandardError => e
        warn "[jekyll-canvas] could not trace #{doc.respond_to?(:relative_path) ? doc.relative_path : doc}: #{e.class}: #{e.message}"
      end

      def on_post_render(doc)
        s = active or return
        # Other documents may print this one's `content` (already converted HTML): keep it clean.
        doc.content = doc.content.gsub(/ data-jc-line="\d+"/, "") if s.target&.annotated && doc.content.is_a?(String)
        s.target&.document = nil
        s.target = nil
      end

      # --- records ----------------------------------------------------------------------

      def lang_of(site)
        (site.respond_to?(:active_lang) && site.active_lang) || site.config["lang"] || "en"
      end

      def default_lang_of(site)
        (site.respond_to?(:default_lang) && site.default_lang) || lang_of(site)
      end

      def languages_of(site)
        site.respond_to?(:languages) && site.languages ? ([default_lang_of(site)] + site.languages).uniq : [lang_of(site)]
      end

      def served_url(site, doc)
        lang = lang_of(site).to_s
        url = doc.url.to_s
        lang == default_lang_of(site).to_s ? url : "/#{lang}#{url}"
      end

      def source_path(site, doc)
        return nil if doc.is_a?(Jekyll::PageWithoutAFile)

        doc.is_a?(Jekyll::Document) ? doc.path : site.in_source_dir(doc.relative_path)
      end

      def build_record(doc, abs)
        site = doc.site
        rec = Record.new
        rec.document = doc
        rec.url = served_url(site, doc)
        rec.lang = lang_of(site).to_s
        rec.file = relative_to_source(site, abs) || doc.relative_path
        rec.kind = doc.is_a?(Jekyll::Document) ? "document" : "page"
        rec.collection = doc.is_a?(Jekyll::Document) ? doc.collection.label : nil
        rec.format = %w[.md .markdown].include?(File.extname(abs).downcase) ? "markdown" : "html"
        data = doc.data
        rec.title = data["title"].is_a?(String) ? data["title"] : nil
        rec.page_id = data["page_id"]&.to_s
        rec.doc_lang = data["lang"]&.to_s
        rec.date = doc.respond_to?(:date) ? doc.date : data["date"]
        rec.order = data["order"]
        rec.redirect = !data["redirect"].nil?
        rec.html = (doc.output_ext == ".html")
        rec.layout_name = data["layout"]
        rec.layouts = layout_chain(site, data["layout"])
        rec.body_start_line = FrontMatter.split(File.binread(abs).force_encoding("UTF-8").scrub).body_start_line
        rec
      end

      def layout_chain(site, name)
        chain = []
        while name && (layout = site.layouts[name.to_s]) && !chain.include?(layout.path)
          chain << layout.path
          name = layout.data["layout"]
        end
        chain.filter_map { |p| relative_to_source(site, p) }
      end

      # --- identity index -----------------------------------------------------------------

      def index_data(site, index)
        data_dir = site.config["data_dir"] || "_data"
        reader = Jekyll::DataReader.new(site)
        walk_data_dir(site, reader, site.in_source_dir(data_dir), [], index)
      end

      def walk_data_dir(site, reader, dir, prefix, index)
        return unless File.directory?(dir)

        Dir.children(dir).sort.each do |entry|
          path = File.join(dir, entry)
          if File.directory?(path)
            walk_data_dir(site, reader, path, prefix + [reader.sanitize_filename(entry)], index)
          elsif entry.match?(DATA_GLOB)
            key = prefix + [reader.sanitize_filename(File.basename(entry, ".*"))]
            value = key.reduce(site.data) { |d, k| d.is_a?(Hash) ? d[k] : nil }
            walk_value(value, [], relative_to_source(site, path) || path, "data", index, 0)
          end
        end
      end

      def walk_value(value, path, file, source, index, depth)
        return if depth > MAX_DEPTH

        case value
        when String then index_string(index, value, path, file, source)
        when Hash then value.each { |k, v| walk_value(v, path + [k], file, source, index, depth + 1) }
        when Array then value.each_with_index { |v, i| walk_value(v, path + [i], file, source, index, depth + 1) }
        end
      end

      def index_string(index, string, path, file, source)
        return if string.length < 2 || index.key?(string)

        index[string] = { file: file, keypath: path, source: source }
      end

      def index_front_matter(site, index)
        docs = site.pages + site.collections.values.flat_map(&:docs)
        docs.each do |doc|
          abs = source_path(site, doc)
          next unless abs && File.file?(abs)

          parts = FrontMatter.split(File.binread(abs).force_encoding("UTF-8").scrub)
          file_data = FrontMatter.load_hash(parts.raw) or next
          rel = relative_to_source(site, abs) or next
          file_data.each do |key, value|
            next if EXCLUDED_FRONT_MATTER_KEYS.include?(key.to_s)

            walk_pair(doc.data[key.to_s], value, [key.to_s], rel, index, 0)
          end
        end
      end

      # Walks the live Jekyll value next to what the file literally contains; only values that
      # exist in the file (and were not altered) are indexed.
      def walk_pair(live, from_file, path, file, index, depth)
        return if depth > MAX_DEPTH

        case from_file
        when String
          index_string(index, live, path, file, "front_matter") if live.is_a?(String) && live == from_file
        when Hash
          return unless live.is_a?(Hash)

          from_file.each { |k, v| walk_pair(live[k], v, path + [k.to_s], file, index, depth + 1) }
        when Array
          return unless live.is_a?(Array)

          from_file.each_with_index { |v, i| walk_pair(live[i], v, path + [i], file, index, depth + 1) }
        end
      end

      # --- markdown line annotation ---------------------------------------------------------

      def annotate_root(root)
        md = md_target or return
        root.children.each do |child|
          next unless ANNOTATED_TYPES.include?(child.type)

          line = child.options[:location] or next
          child.attr["data-jc-line"] = (md.body_start_line + line - 1).to_s
        end
      end
    end

    # --- patches -------------------------------------------------------------------------

    module VariableLookupPatch
      def evaluate(context)
        result = super
        Tracer.note(result)
        result
      end
    end

    module IncludeTagPatch
      def render(context)
        result = super
        Tracer.note_include(self, context)
        result
      end
    end

    module RendererPatch
      def convert(content)
        s = Tracer.active
        target = s&.target
        return super unless target && target.document.equal?(document) && !document.is_a?(Jekyll::Excerpt)

        # Line numbers only hold when Liquid kept the body's line structure.
        if document.content.count("\n") == content.count("\n")
          s.md_target = MdTarget.new(body_start_line: target.body_start_line)
          target.annotated = true
        end
        begin
          super
        ensure
          s.md_target = nil
        end
      end
    end

    # Jekyll caches Markdown output by content; a traced conversion must not read or fill that cache.
    module MarkdownConverterPatch
      def convert(content)
        return super unless Tracer.md_target

        setup
        @parser.convert(content)
      end
    end

    module KramdownHtmlPatch
      def inner(el, indent)
        Tracer.annotate_root(el) if el.type == :root
        super
      end
    end

    def self.install!
      return if @installed

      @installed = true
      Liquid::VariableLookup.prepend(VariableLookupPatch)
      Jekyll::Tags::IncludeTag.prepend(IncludeTagPatch)
      Jekyll::Tags::OptimizedIncludeTag.prepend(IncludeTagPatch)
      Jekyll::Renderer.prepend(RendererPatch)
      Jekyll::Converters::Markdown.prepend(MarkdownConverterPatch)
      Kramdown::Converter::Html.prepend(KramdownHtmlPatch)

      Jekyll::Hooks.register(:site, :post_read, priority: 1) { |site| on_post_read(site) }
      Jekyll::Hooks.register(%i[pages documents], :pre_render) { |doc, _payload| on_pre_render(doc) }
      Jekyll::Hooks.register(%i[pages documents], :post_render) { |doc| on_post_render(doc) }
    end
  end
end

JekyllCanvas::Tracer.install!
