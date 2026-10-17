# frozen_string_literal: true

require "kramdown"
require_relative "front_matter"

module JekyllCanvas
  # Finds rendered text in the sources that can contain it literally: the page's own body (HTML
  # pages only), its layouts and the includes it rendered.
  class Locator
    LIQUID_SPAN = /\{\{.*?\}\}|\{%.*?%\}/m
    CORE_ENTITIES = { "&" => %w[amp], "<" => %w[lt], ">" => %w[gt], "\"" => %w[quot], "'" => %w[apos], " " => %w[nbsp] }.freeze
    CONTEXT = 28

    def self.names_by_code_point
      @names_by_code_point ||= Kramdown::Utils::Entities::ENTITY_TABLE.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(cp, name), h|
        h[cp] << name
      end
    rescue StandardError
      {}
    end

    def initialize(root)
      @root = root
    end

    # record: JekyllCanvas::Record. Returns candidate hashes per spec-api.md.
    def locate(record, text)
      regex = self.class.regex_for(text)
      return [] unless regex

      files(record).flat_map { |file, skip_front_matter| search(file, regex, skip_front_matter) }
    end

    def self.regex_for(text)
      tokens = text.to_s.strip.split(/[[:space:]&&[^ ]]+/).reject(&:empty?)
      return nil if tokens.empty?

      body = tokens.map { |t| t.each_char.map { |c| char_pattern(c) }.join }.join('\s+')
      first = tokens.first[0]
      last = tokens.last[-1]
      lead = first.match?(/[[:alnum:]]/) ? '(?<![[:alnum:]])' : ""
      trail = last.match?(/[[:alnum:]]/) ? '(?![[:alnum:]])' : ""
      Regexp.new("#{lead}#{body}#{trail}")
    end

    def self.char_pattern(char)
      literal = Regexp.escape(char)
      names = CORE_ENTITIES[char] || (char.ord > 127 ? names_by_code_point[char.ord] : nil)
      return literal unless names || CORE_ENTITIES.key?(char) || char.ord > 127

      cp = char.ord
      alternatives = [literal]
      alternatives.concat((names || []).map { |n| "&#{n};" })
      alternatives << "&\#0*#{cp};" << "(?i:&\#x0*#{cp.to_s(16)};)"
      "(?:#{alternatives.join('|')})"
    end

    private

    def files(record)
      list = []
      list << [record.file, true] if record.format == "html"
      record.layouts.each { |f| list << [f, true] }
      record.includes.each { |f| list << [f, false] }
      list.uniq
    end

    def search(file, regex, skip_front_matter)
      path = File.join(@root, file)
      return [] unless File.file?(path)

      content = File.binread(path).force_encoding("UTF-8").scrub
      from = skip_front_matter ? FrontMatter.split(content).body_start : 0
      spans = liquid_spans(content)
      found = []
      pos = from
      while (m = regex.match(content, pos))
        pos = [m.end(0), m.begin(0) + 1].max
        next if spans.any? { |s, e| m.begin(0) < e && m.end(0) > s }

        found << candidate(file, content, m.begin(0), m.end(0))
      end
      found
    end

    def liquid_spans(content)
      spans = []
      content.scan(LIQUID_SPAN) { spans << [Regexp.last_match.begin(0), Regexp.last_match.end(0)] }
      spans
    end

    def candidate(file, content, start, finish)
      before = content[[start - CONTEXT, 0].max...start].gsub(/\s+/, " ")
      after = content[finish, CONTEXT].to_s.gsub(/\s+/, " ")
      snippet = "#{start > CONTEXT ? '…' : ''}#{before}#{content[start...finish].gsub(/\s+/, ' ')}#{after}#{finish + CONTEXT < content.length ? '…' : ''}"
      { file: file, start: start, end: finish, line: content[0...start].count("\n") + 1,
        old_text: content[start...finish], snippet: snippet }
    end
  end
end
