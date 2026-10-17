# frozen_string_literal: true

require "psych"
require "date"
require "time"

module JekyllCanvas
  # Splits a file into front matter and body using Jekyll's own regexp semantics.
  module FrontMatter
    REGEXP = /\A(---\s*\n.*?\n?)^((---|\.\.\.)\s*$\n?)/m
    PERMITTED = [Date, Time, Symbol].freeze

    # raw: YAML text between the delimiters (nil when there is no front matter);
    # yaml_start/yaml_end: character offsets of that text; body_start: offset where the body begins.
    Parts = Struct.new(:raw, :body, :body_start_line, :yaml_start, :yaml_end, :body_start, keyword_init: true) do
      def front_matter?
        !raw.nil?
      end
    end

    module_function

    def split(content)
      m = REGEXP.match(content)
      return Parts.new(raw: nil, body: content, body_start_line: 1, yaml_start: nil, yaml_end: nil, body_start: 0) unless m

      yaml_start = content.index("\n") + 1
      yaml_end = m.end(1)
      Parts.new(
        raw: content[yaml_start...yaml_end],
        body: m.post_match,
        body_start_line: m[0].count("\n") + 1,
        yaml_start: yaml_start,
        yaml_end: yaml_end,
        body_start: m.end(0)
      )
    end

    # The front matter as a Hash, or nil when absent/invalid/not a mapping.
    def load_hash(raw)
      return nil if raw.nil?

      data = Psych.safe_load(raw, permitted_classes: PERMITTED, aliases: true)
      data.is_a?(Hash) ? data : (raw.strip.empty? || data.nil? ? {} : nil)
    rescue Psych::Exception
      nil
    end
  end
end
