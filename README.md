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

### Reachability guard

`OpenApiGenerator::Completeness.unreachable(config:, samples: {})` fills each documented
operation's path with sample values (`"1"` unless `samples` names the param) and recognizes it
against `Rails.application.routes`. It returns the `"VERB /path"` operations whose recognized
route is missing or whose recognized controller and action differ from the documented ones.
Host tests assert it is empty (`samples: { "orgslug" => "0000001" }` for org-slug paths).

Limits: recognition runs without a request, so routes guarded by request-env lambda
constraints (headers, host, subdomain) cannot be satisfied and show up as unreachable, and a
path param with a constraint (for example `production_type: /eggs|milk/`) needs a `samples`
value that matches it.

### Engine mounts

Engine routes are documented under the engine's mount point in the host routes. An engine
with routes but no mount point is unreachable, so it is skipped (it is never treated as
mounted at the root). An engine mounted at `/` keeps root paths.

### Required fields (`!`)

`api_params permit:` accepts a `!` suffix on a field type (`title: :string!`) and on the
key of a nested object or array of objects (`"actor!": { kind: :string! }`,
`"lines!": [[ sku: :string! ]]`). The generated schema emits `required` at every object
level (top level, nested objects and array items).

`!` is schema-only unless `config.enforce_required = true`. With enforcement on (default
`false`, boolean only), `permitted` raises `ActionController::ParameterMissing` for any
top-level `!` field whose key is missing or `nil`. `false` and `""` are present values
and pass to the model. Nested `!` fields are not enforced. Wrapped and flat (no wrapper)
bodies are both enforced. See the CHANGELOG for the sweep a host must do before enabling.

### Response schemas (`api_response`)

`api_response :show, serializer: Serializer` is the preferred form. The schema comes from
`Serializer.open_api_schema`; with `collection: true` the response uses
`Serializer.open_api_collection_schema` when the serializer defines it, else an array of
`open_api_schema`. Declare serializer schemas to match exactly what `render` emits.

`api_response :show, model: Model` is the legacy fallback: it emits every column of the
model. Set `config.response_column_denylist` (strings and Regexps, default `[]`) to leave
columns such as `idempotency_key` or `*_fingerprint` out of those schemas. The denylist
applies only to this fallback, never to serializer schemas or request schemas.

`envelope: :data` wraps the schema as `{ data: X }`, and collections as
`{ data: [X], meta: { type: object } }` (components `<Name>Envelope` and
`<Name>ListEnvelope`, both with `required: ["data"]`; `meta` is optional because not every endpoint paginates; `X` stays registered as `<Name>`). With an envelope the serializer's
`open_api_schema` is the item `X` and `open_api_collection_schema` is not used. Set a
class-level default with `self.open_api_generator_response_envelope = :data` (inherited;
`:none` or an explicit `envelope: :none` turns it off). With nothing set, output is unchanged.

### Caching

The generated spec is cached for `config.cache_ttl` (not in development). The default
`cache_key` carries a discriminator: a digest of the release marker (`Rails.application.config.x.release`, else the `KAMAL_VERSION` environment variable Kamal sets on deploy) joined with a digest of the route set (verb, path, controller, action only, so changes to `swagger`/`api_params`/`api_response`/serializers alone are not seen; with no release marker such a deploy can serve a stale spec for up to `cache_ttl`). A host-set `config.cache_key` is used verbatim.

`config.scalar_overrides = { uuid: { type: "string", pattern: "..." } }` replaces the schema for a scalar type everywhere `TypeMapper.scalar` is used (`api_params` tokens and model schemas).
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
