# frozen_string_literal: true

module JekyllCanvas
  # What the tracer learned about one rendered page/document (one per served URL).
  class Record
    attr_accessor :url, :lang, :file, :kind, :collection, :format, :title, :page_id, :doc_lang,
                  :date, :order, :redirect, :html, :body_start_line, :layouts, :includes,
                  :translations, :document, :layout_name, :annotated

    attr_reader :strings

    def initialize
      @layouts = []
      @includes = []
      @strings = {}
      @translations = []
    end

    # entry: {file:, keypath:, source:}; deduplicated by (file, keypath).
    def add_string(entry, value)
      key = [entry[:file], entry[:keypath]]
      @strings[key] ||= entry.merge(value: value.dup)
    end

    def add_include(path)
      @includes << path unless @includes.include?(path)
    end

    def markdown?
      format == "markdown"
    end
  end

  # All records of one build, keyed by served URL.
  class Records
    include Enumerable

    def initialize
      @by_url = {}
    end

    def add(record)
      @by_url[record.url] = record
    end

    def [](url)
      @by_url[url]
    end

    def each(&block)
      @by_url.each_value(&block)
    end

    def size
      @by_url.size
    end

    # Fills `translations` for every record: records sharing a page_id (within a collection),
    # or rendered from the same file, are translations of each other.
    def finalize!(languages)
      groups = group_by { |r| r.page_id.to_s.empty? ? ["file", r.file] : ["id", r.collection, r.page_id] }
      groups.each_value do |members|
        entries = members.map { |r| { lang: r.lang, url: r.url, file: r.file } }
                         .uniq { |e| [e[:lang], e[:url]] }
                         .sort_by { |e| [languages.index(e[:lang]) || languages.length, e[:url]] }
        members.each { |r| r.translations = entries }
      end
    end
  end
end
