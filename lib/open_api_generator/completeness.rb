# frozen_string_literal: true

module OpenApiGenerator
  # Audits write operations for a machine-readable request body declaration.
  module Completeness
    Offense = Struct.new(:controller, :action, :verb, :path, keyword_init: true)
    WRITE = %w[POST PUT PATCH].freeze

    # @param include_ignored [Boolean] also audit controllers in `:ignore` mode
    #   (hidden from the spec, such as machine-only controllers) for request bodies
    def self.audit(config:, include_ignored: false)
      SpecBuilder.__send__(:discover_operations, config, include_ignored: include_ignored).filter_map do |operation|
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
