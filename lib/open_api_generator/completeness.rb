# frozen_string_literal: true

module OpenApiGenerator
  # Audits write operations for a machine-readable request body declaration.
  module Completeness
    Offense = Struct.new(:controller, :action, :verb, :path, keyword_init: true)
    WRITE = %w[POST PUT PATCH].freeze

    def self.audit(config:)
      SpecBuilder.__send__(:discover_operations, config).filter_map do |operation|
        next unless WRITE.include?(operation[:verb].to_s.upcase)
        next if operation[:has_request_body]

        Offense.new(
          controller: operation[:controller],
          action: operation[:action],
          verb: operation[:verb],
          path: operation[:path]
        )
      end
    end
  end
end
