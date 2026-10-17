# frozen_string_literal: true

module JekyllCanvas
  # An error that maps onto an API response: `code` is one of forbidden, not_found, invalid,
  # conflict, build_failed, git_failed.
  class ApiError < StandardError
    STATUS = { "forbidden" => 403, "not_found" => 404, "invalid" => 422, "conflict" => 409,
               "build_failed" => 500, "git_failed" => 500 }.freeze

    attr_reader :code

    def initialize(code, message)
      super(message)
      @code = code
    end

    def status
      STATUS.fetch(code, 500)
    end
  end
end
