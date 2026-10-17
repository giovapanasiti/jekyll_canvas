# frozen_string_literal: true

require "psych"
require "date"
require "time"

module JekyllCanvas
  # Byte-preserving YAML value editor.
  #
  # Psych gives node positions; only the bytes of the edited value are replaced, so comments,
  # key order, blank lines, quoting of other keys and line endings survive. Every result is
  # re-parsed and compared with the expected structure before it is returned.
  module YamlEditor
    class Error < StandardError; end
    class Unsupported < Error; end
    class VerificationFailed < Error; end
    class NotFound < Error; end
    class Conflict < Error; end
    class Invalid < Error; end

    UNSET = Object.new.tap { |o| def o.inspect = "UNSET" }.freeze
    PERMITTED = [Date, Time, Symbol].freeze
    Nodes = Psych::Nodes
    PLAIN_START_FORBIDDEN = "-?:,[]{}#&*!|>'\"%@`"
    CONTROL = /[\x00-\x1F\x7F\u0085  ﻿]/
    LINE_BREAK = /\r\n|[\n\r\u0085  ]/

    module_function

    # Value at keypath. Raises NotFound / Invalid.
    def get(source, keypath)
      found, value = lookup(load(source), Array(keypath))
      raise NotFound, "key path not found: #{Array(keypath).inspect}" unless found

      value
    end

    # Returns the new source. `old:` (when given) must equal the current value, else Conflict.
    # Without `old:` and with a missing key the key is added to its parent mapping.
    def set(source, keypath, new_value, old: UNSET)
      keypath = Array(keypath)
      raise Invalid, "empty key path" if keypath.empty?

      new_value = check_value(new_value)
      original = load(source)
      exists, current = lookup(original, keypath)
      if !old.equal?(UNSET) && (!exists || current != old)
        raise Conflict, "current value differs from the expected one"
      end
      return source if exists && current == new_value && current.class == new_value.class

      expected = original.nil? ? {} : Marshal.load(Marshal.dump(original))
      assign(expected, keypath, new_value)

      %i[auto double].each do |mode|
        result = edit(source, keypath, new_value, exists, mode)
        return result if verified?(result, expected)
      rescue Unsupported
        raise if mode == :double
      end
      raise VerificationFailed, "the edited YAML does not match the expected structure"
    end

    # --- loading and structure helpers ---------------------------------------------------

    def load(source)
      Psych.safe_load(source, permitted_classes: PERMITTED, aliases: true)
    rescue Psych::Exception => e
      raise Invalid, "invalid YAML: #{e.message}"
    end

    def verified?(source, expected)
      load(source) == expected
    rescue Invalid
      false
    end

    def check_value(value)
      case value
      when String, Integer, Float, true, false, nil then value
      when Array
        raise Invalid, "arrays may only contain scalars" unless value.all? { |v| scalar?(v) }

        value
      else raise Invalid, "unsupported value type #{value.class}"
      end
    end

    def scalar?(value)
      [String, Integer, Float, TrueClass, FalseClass, NilClass].any? { |k| value.is_a?(k) }
    end

    def lookup(data, keypath)
      keypath.each do |seg|
        case data
        when Hash
          pair = data.find { |k, _| k.to_s == seg.to_s }
          return [false, nil] unless pair

          data = pair[1]
        when Array
          idx = Integer(seg.to_s, exception: false)
          return [false, nil] if idx.nil? || idx.negative? || idx >= data.length

          data = data[idx]
        else
          return [false, nil]
        end
      end
      [true, data]
    end

    def assign(data, keypath, value)
      parent_exists, parent = lookup(data, keypath[0...-1])
      raise NotFound, "parent not found" unless parent_exists

      seg = keypath.last
      case parent
      when Hash
        key = parent.keys.find { |k| k.to_s == seg.to_s } || seg.to_s
        parent[key] = value
      when Array
        idx = Integer(seg.to_s, exception: false)
        raise NotFound, "bad index" if idx.nil? || idx > parent.length

        parent[idx] = value
      else raise NotFound, "parent is not a collection"
      end
    end

    # --- editing -------------------------------------------------------------------------

    # Source text with line/column to character offset conversion.
    class Doc
      attr_reader :source, :root, :nl

      def initialize(source)
        @source = source
        parsed = Psych.parse(source)
        @root = parsed ? parsed.root : nil
        @nl = source.include?("\r\n") ? "\r\n" : "\n"
        @starts = [0]
        source.scan(LINE_BREAK) { @starts << Regexp.last_match.end(0) }
      end

      def offset(line, col)
        base = @starts[line] || @source.length
        [base + col, @source.length].min
      end

      def start_of(node) = offset(node.start_line, node.start_column)
      def end_of(node) = offset(node.end_line, node.end_column)

      # Offset of the line terminator that ends the line containing `pos` (or EOF).
      def line_end(pos)
        idx = @source.index(LINE_BREAK, pos)
        idx || @source.length
      end

      def blank?(from, to) = @source[from...to].strip.empty?
    end

    def edit(source, keypath, value, exists, mode)
      doc = Doc.new(source)
      if exists
        node, info = locate(doc.root, keypath)
        replace(doc, node, info, value, mode)
      else
        add_key(doc, keypath, value, mode)
      end
    end

    # Walks the node tree; info carries flow-ness and the indent of the enclosing collection.
    def locate(root, keypath)
      node = root
      info = { flow: false, indent: 0 }
      keypath.each do |seg|
        case node
        when Nodes::Mapping
          info[:flow] ||= node.style == Nodes::Mapping::FLOW
          pair = node.children.each_slice(2).find { |k, _| k.is_a?(Nodes::Scalar) && k.value == seg.to_s }
          if pair.nil?
            merge = node.children.each_slice(2).any? { |k, _| k.is_a?(Nodes::Scalar) && k.value == "<<" }
            raise Unsupported, "the key may come from a YAML merge key" if merge

            raise NotFound, "key path not found"
          end
          info[:indent] = pair[0].start_column
          node = pair[1]
        when Nodes::Sequence
          info[:flow] ||= node.style == Nodes::Sequence::FLOW
          idx = Integer(seg.to_s, exception: false)
          raise NotFound, "bad sequence index" if idx.nil? || node.children[idx].nil?

          info[:indent] = node.start_column
          node = node.children[idx]
        when Nodes::Alias
          raise Unsupported, "key path goes through a YAML alias"
        else
          raise NotFound, "key path not found"
        end
      end
      [node, info]
    end

    def replace(doc, node, info, value, mode)
      raise Unsupported, "value is a YAML alias" if node.is_a?(Nodes::Alias)
      raise Unsupported, "value has an anchor or tag" if node.anchor || node.tag

      case node
      when Nodes::Scalar
        raise Unsupported, "cannot turn a scalar into a list" if value.is_a?(Array)

        block_style?(node) ? replace_block(doc, node, info, value, mode) : replace_flow_scalar(doc, node, info, value, mode)
      when Nodes::Sequence
        raise Unsupported, "only lists of scalars can be replaced" unless value.is_a?(Array)

        replace_sequence(doc, node, info, value, mode)
      else
        raise Unsupported, "cannot replace a mapping"
      end
    end

    def block_style?(node)
      [Nodes::Scalar::LITERAL, Nodes::Scalar::FOLDED].include?(node.style)
    end

    def replace_flow_scalar(doc, node, info, value, mode)
      s = doc.start_of(node)
      e = doc.end_of(node)
      check_slice!(doc, node, s, e)
      text = render_scalar(value, node.style, info[:flow], mode)
      text = " #{text}" if s == e # empty value: `key:` has the mark right after the colon
      "#{doc.source[0...s]}#{text}#{doc.source[e..]}"
    end

    # Guards against offset surprises (exotic line breaks, etc.): the slice must parse back to the node's value.
    def check_slice!(doc, node, s, e)
      return if s == e

      parsed = Psych.parse(doc.source[s...e])&.root
      ok = parsed.is_a?(Nodes::Scalar) && parsed.value == node.value
      raise Unsupported, "could not locate the value reliably" unless ok
    rescue Psych::Exception
      raise Unsupported, "could not locate the value reliably"
    end

    # --- scalar rendering ----------------------------------------------------------------

    def render_scalar(value, style, flow, mode)
      return literal_scalar(value) unless value.is_a?(String)
      return double_quote(value) if mode == :double

      case style
      when Nodes::Scalar::DOUBLE_QUOTED then double_quote(value)
      when Nodes::Scalar::SINGLE_QUOTED then single_quotable?(value) ? single_quote(value) : double_quote(value)
      else plain_ok?(value, flow) ? value : double_quote(value)
      end
    end

    def literal_scalar(value)
      case value
      when nil then "null"
      when true, false, Integer then value.to_s
      when Float
        if value.nan? then ".nan"
        elsif value.infinite? then value.positive? ? ".inf" : "-.inf"
        else value.to_s
        end
      else raise Invalid, "unsupported scalar #{value.class}"
      end
    end

    def plain_ok?(str, flow = false)
      return false if str.empty? || str.match?(/\A\s|\s\z/) || str.match?(CONTROL) || str.include?("\t")
      return false if PLAIN_START_FORBIDDEN.include?(str[0])
      return false if str.include?(": ") || str.include?(" #") || str.end_with?(":")
      return false if flow && str.match?(/[,\[\]{}]/)

      loaded = Psych.safe_load(str, permitted_classes: PERMITTED)
      loaded.is_a?(String) && loaded == str
    rescue Psych::Exception
      false
    end

    def single_quotable?(str)
      !str.match?(CONTROL) && !str.include?("\t")
    end

    def single_quote(str) = "'#{str.gsub("'", "''")}'"

    ESCAPES = {
      "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n", "\r" => "\\r", "\t" => "\\t",
      "\e" => "\\e", "\0" => "\\0", "\u0085" => "\\N", " " => "\\L", " " => "\\P"
    }.freeze

    def double_quote(str)
      body = str.each_char.map do |c|
        ESCAPES.fetch(c) do
          if c.ord < 0x20 || c.ord == 0x7F then format("\\x%02X", c.ord)
          elsif c == "﻿" then "\\uFEFF"
          else c
          end
        end
      end.join
      "\"#{body}\""
    end

    # --- sequences -----------------------------------------------------------------------

    def render_flow_sequence(values, mode)
      "[#{values.map { |v| render_scalar(v, Nodes::Scalar::PLAIN, true, mode) }.join(', ')}]"
    end

    def replace_sequence(doc, node, info, values, mode)
      unless node.children.all? { |c| c.is_a?(Nodes::Scalar) && !block_style?(c) && !c.anchor && !c.tag }
        raise Unsupported, "list items are not plain scalars"
      end

      s = doc.start_of(node)
      if node.style == Nodes::Sequence::FLOW
        e = doc.end_of(node)
        return "#{doc.source[0...s]}#{render_flow_sequence(values, mode)}#{doc.source[e..]}"
      end

      region = doc.source[s...doc.end_of(node)]
      e = s + region.rindex(/\S/).to_i + 1
      e = [e, doc.end_of(node.children.last)].max
      if values.empty?
        colon = doc.source[0...s].rindex(/\S/)
        raise Unsupported, "cannot empty this list" unless colon && doc.source[colon] == ":"

        return "#{doc.source[0..colon]} []#{doc.source[e..]}"
      end

      indent = " " * node.start_column
      items = values.map { |v| "- #{render_scalar(v, Nodes::Scalar::PLAIN, false, mode)}" }
      "#{doc.source[0...s]}#{items.join("#{doc.nl}#{indent}")}#{doc.source[e..]}"
    end

    # --- block scalars -------------------------------------------------------------------

    def replace_block(doc, node, info, value, mode)
      return replace_block_region(doc, node, render_scalar(value, nil, false, mode)) if mode == :double || !value.is_a?(String)

      src = doc.source
      s = doc.start_of(node)
      header_end = doc.line_end(s)
      m = src[s...header_end].match(/\A([|>])([-+0-9]*)(.*)\z/m) or raise Unsupported, "unexpected block scalar header"
      folded = m[1] == ">"
      tail = m[3]

      content = value.sub(/\n+\z/, "")
      newlines = value.length - content.length
      chomp = newlines.zero? ? "-" : (newlines == 1 ? "" : "+")

      region_end = block_region_end(doc, node, header_end, m[2].include?("+") && chomp == "+")
      indent_width = block_indent(doc, header_end, region_end, info)
      indent = " " * indent_width

      lines = content.empty? ? [] : (folded ? folded_lines(content) : content.split("\n", -1))
      explicit = ""
      if lines.first&.empty? || lines.find { |l| !l.empty? }&.start_with?(" ")
        digit = indent_width - [info[:indent], 0].max
        raise Unsupported, "indentation indicator out of range" unless (1..9).cover?(digit)

        explicit = digit.to_s
      end

      out = "#{m[1]}#{explicit}#{chomp}#{tail}"
      out += lines.map { |l| l.empty? ? doc.nl : "#{doc.nl}#{indent}#{l}" }.join
      out += doc.nl * (newlines - 1) if newlines > 1
      # When the region swallowed the final line terminator (kept trailing blank lines), give it back.
      out += doc.nl if chomp == "+" && region_end > s && src[region_end - 1].match?(/[\n\r\u0085\u2028\u2029]/)
      "#{src[0...s]}#{out}#{src[region_end..]}"
    end

    def folded_lines(text)
      out = []
      text.split(/(\n+)/).each_slice(2) do |line, seps|
        out << line
        (seps.to_s.length).times { out << "" } if seps
      end
      out
    end

    # End of the replaced region: end of the last non-blank content line (terminator excluded),
    # or Psych's own end when trailing blank lines are significant (`|+` kept as `|+`).
    def block_region_end(doc, node, header_end, keep)
      e = doc.end_of(node)
      return e if keep

      region = doc.source[header_end...e].to_s
      idx = region.rindex(/\S/)
      idx ? doc.line_end(header_end + idx) : header_end
    end

    def block_indent(doc, header_end, region_end, info)
      body = doc.source[header_end...region_end].to_s
      line = body.split(LINE_BREAK).find { |l| !l.strip.empty? }
      return line[/\A */].length if line

      [info[:indent], 0].max + 2
    end

    def replace_block_region(doc, node, text)
      s = doc.start_of(node)
      e = block_region_end(doc, node, doc.line_end(s), false)
      "#{doc.source[0...s]}#{text}#{doc.source[e..]}"
    end

    # --- adding keys ---------------------------------------------------------------------

    def add_key(doc, keypath, value, mode)
      key = keypath.last
      raise Invalid, "new keys must be strings" unless key.is_a?(String)

      rendered_key = plain_ok?(key) ? key : double_quote(key)
      rendered_value = value.is_a?(Array) ? render_flow_sequence(value, mode) : render_scalar(value, Nodes::Scalar::PLAIN, false, mode)
      src = doc.source

      if doc.root.nil?
        raise NotFound, "parent not found" unless keypath.length == 1

        sep = src.empty? || src.match?(LINE_BREAK_AT_END) ? "" : doc.nl
        return "#{src}#{sep}#{rendered_key}: #{rendered_value}#{doc.nl}"
      end

      parent, = locate(doc.root, keypath[0...-1])
      raise Unsupported, "parent is not a block mapping" unless parent.is_a?(Nodes::Mapping) && parent.style != Nodes::Mapping::FLOW
      raise Unsupported, "parent is empty" if parent.children.empty?

      indent = " " * parent.children.first.start_column
      insert_at = doc.line_end(content_end(doc, parent.children.last))
      "#{src[0...insert_at]}#{doc.nl}#{indent}#{rendered_key}: #{rendered_value}#{src[insert_at..]}"
    end

    LINE_BREAK_AT_END = /(?:\r\n|[\n\r\u0085  ])\z/

    # Offset just after the last content character of `node` (ignores trailing blank lines).
    def content_end(doc, node)
      case node
      when Nodes::Mapping
        return doc.end_of(node) if node.style == Nodes::Mapping::FLOW || node.children.empty?

        content_end(doc, node.children.last)
      when Nodes::Sequence
        return doc.end_of(node) if node.style == Nodes::Sequence::FLOW || node.children.empty?

        content_end(doc, node.children.last)
      when Nodes::Scalar
        if block_style?(node)
          s = doc.start_of(node)
          header_end = doc.line_end(s)
          block_region_end(doc, node, header_end, false)
        else
          doc.end_of(node)
        end
      else doc.end_of(node)
      end
    end
  end
end
