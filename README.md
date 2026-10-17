# OpenApiGenerator

## Usage

Mount the engine and configure it in an initializer:

```ruby
mount OpenApiGenerator::Engine => "/api/v1/docs"

OpenApiGenerator.configure do |config|
  config.title = "My API"
  config.authorize = ->(controller) { controller.request.local? }
end
```

The spec is served at `spec.json` and `spec.yaml` (plus `routes.json` in development).
The root key is `openapi: "3.0.3"`.

### Restricting access (`config.authorize`)

`config.authorize` is a callable that takes the `OpenApiGenerator::OpenApiController`
instance. It runs as the first before_action, before any cache read or spec build, for
`spec.json`, `spec.yaml` and `routes.json`. A falsy result answers `404 Not Found`
with an empty body. The default is `nil`, which leaves the docs public. Core-backed
hosts use `Core::OpenApi.operator_session_authorizer`.

### Completeness audit

`OpenApiGenerator::Completeness.audit(config: config)` lists POST/PUT/PATCH operations
without an `api_params` declaration. Controllers in `swagger_ignore!` mode are skipped
unless you pass `include_ignored: true`, which audits hidden controllers (for example
machine-only endpoints) for request bodies too.

### Caching

The generated spec is cached for `config.cache_ttl` (not in development). The default
`cache_key` carries a discriminator: `Rails.application.config.x.release` when set,
otherwise a digest of the route set (verb, path, controller, action only, so changes to `swagger`/`api_params`/`api_response`/serializers alone are not seen; set `x.release` from the deploy revision). A host-set `config.cache_key` is used verbatim.
A failed build is never cached; with no earlier entry the error propagates.

## Installation
Add this line to your application's Gemfile:

```ruby
gem "open_api_generator"
```

And then execute:
```bash
$ bundle install
```

Or install it yourself as:
```bash
$ gem install open_api_generator
```

## Contributing

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
