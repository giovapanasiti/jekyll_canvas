# frozen_string_literal: true

module JekyllCanvas
  # An error that maps onto an API response: `code` is one of forbidden, not_found, invalid,
  # conflict, build_failed, git_failed, liquid_syntax (a 422 for op "file").
  class ApiError < StandardError
    STATUS = { "forbidden" => 403, "not_found" => 404, "invalid" => 422, "conflict" => 409,
               "build_failed" => 500, "liquid_syntax" => 422, "git_failed" => 500 }.freeze

    attr_reader :code, :extra

    # `extra` is merged into the JSON error body (e.g. `line` for liquid_syntax).
    def initialize(code, message, extra: {})
      super(message)
      @code = code
      @extra = extra
    end

    def status
      STATUS.fetch(code, 500)
    end
  end
end
