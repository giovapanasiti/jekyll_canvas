# frozen_string_literal: true

require "kramdown"

module JekyllCanvas
  # Top-level Markdown blocks of a body with their line ranges (1-based, relative to the body).
  module MarkdownBlocks
    Block = Struct.new(:start_line, :end_line, :type, :header_level, keyword_init: true)

    TYPES = %i[p header ul ol blockquote codeblock html_element table hr math dl].freeze

    module_function

    def options_for(config)
      opts = (config || {}).each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
      opts[:input] = "GFM" if opts[:input].to_s.empty?
      opts
    end

    def blocks(body, kramdown_options = {})
      opts = options_for(kramdown_options)
      root = Kramdown::Document.new(body, opts).root
      starts = root.children.select { |el| el.type != :blank && el.options[:location] }
      lines = body.lines
      starts.each_with_index.map do |el, i|
        first = el.options[:location]
        last = i + 1 < starts.length ? starts[i + 1].options[:location] - 1 : lines.length
        last = trim_trailing(lines, first, last)
        Block.new(start_line: first, end_line: last, type: TYPES.include?(el.type) ? el.type : :other,
                  header_level: el.type == :header ? el.options[:level] : nil)
      end
    end

    # Drops trailing blank lines and block IALs that belong to the next block
    # (an IAL separated from this block by a blank line).
    def trim_trailing(lines, first, last)
      loop do
        last -= 1 while last > first && lines[last - 1].to_s.strip.empty?
        ial = lines[last - 1].to_s.match?(/\A\{:[^}]*\}\s*\z/)
        break unless ial && last - 1 > first && lines[last - 2].to_s.strip.empty?

        last -= 2
      end
      last
    end

    # The block that contains `line` (body-relative), or nil.
    def block_at(body, line, kramdown_options = {})
      blocks(body, kramdown_options).find { |b| line.between?(b.start_line, b.end_line) }
    end
  end
end
