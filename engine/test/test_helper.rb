# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
Encoding.default_external = Encoding::UTF_8
Warning[:deprecated] = false

