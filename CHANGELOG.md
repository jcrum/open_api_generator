# Changelog

## Unreleased

- Add `Configuration#authorize` (callable taking the controller; `nil` = public). It runs
  before the cache read and the build, and a falsy result answers an empty `404` for
  `spec.json`, `spec.yaml` and `routes.json` (security finding OAG-01).
- Add `Completeness.audit(include_ignored: true)` so `swagger_ignore!` controllers with
  request bodies are still audited.
- The default `cache_key` now includes a discriminator: `Rails.application.config.x.release` when set,
  else a digest of the route set (verb, path, controller, action) (OAG-OW-02). A host-set `cache_key`
  is unchanged. The digest does not see changes to `swagger`, `api_params`, `api_response` or
  serializers, so a deploy that changes only those keeps the key for up to `cache_ttl`. No Paxfish
  host sets `config.x.release` yet. Follow-up: each host should set it from the deploy revision.
  Failed builds are not cached.
- `Configuration#authorize=` raises `ArgumentError` unless given nil or a callable.
- Emit the root key as `openapi: "3.0.3"` instead of `open_api` (OAG-STD-001). Consumers
  that read the root key must read `openapi`.
- Skip an engine's routes when it has no mount point instead of documenting it at the root
  (OAG-02). `RouteDiscovery.find_engine_mount_point` now returns `nil` for an unmounted engine.
  An engine mounted at `/` keeps root paths. Hosts that relied on an unmounted engine appearing
  in the spec lose those paths (Boards lost the unreachable Activities `/events` API).
- Add `Completeness.unreachable(config:, samples:)`, a guard listing documented operations whose
  path the host routes do not recognize, or recognize as a different controller/action.
  `permitted` now passes the route's path parameter names so enforcement ignores them for flat bodies.
- Emit `required` at every object level, not only the top level: nested objects and array
  items (OAG-06, OAG-STD-002). A trailing `!` on a nested object or array-of-object key marks
  that property itself required (`"actor!": { kind: :string! }`). Consumers that read nested
  schemas (clients, MCP tools) now see nested `required`.
- Add `Configuration#enforce_required` (default `false`, boolean only, else `ArgumentError`).
  When true, `permit` raises `ActionController::ParameterMissing` for a TOP-LEVEL `!` field whose
  key is missing or nil (`false` and `""` pass); nested fields are not enforced; wrapped and flat
  bodies are both enforced. `!` stays schema-only while it is off. No Paxfish host enables it.
  Sweep a host must do before enabling:
  - No `permitted` call in a `before_action` that runs ahead of `authorize_actions`: the
    `ParameterMissing` (400) would answer before authorization and leak that a record exists.
  - Review `!` on update/destroy declarations: a partial update or a destroy that never sends
    the field would start failing (for example boards `card_children_controller.rb` ~L14,
    crummy-reader-service `folders_controller.rb` ~L5, milk-and-eggs
    `app/controllers/api/production_favorites_controller.rb` ~L5-6, where `production_type: :string!`
    is also a path segment (`POST production/favorites/:production_type`): enforcement ignores
    path params for flat bodies, so a client that sends only the path segment would start getting
    400. Drop the `!` or require the body field deliberately).
  - Enforcement checks the permitted output, so a wrong-shaped value (`title: {}`) counts as missing.
  - Booleans such as `show_done_well: :boolean!` count `false` as present, so they are safe, but
    confirm clients send JSON `false` and not an omitted key.
- Follow-up: enable `Core::OpenApi.operator_session_authorizer` in pfos once its in-progress
  work lands (pfos was not touched in this batch).

## 0.2.0 - 2026-08-14

- Add `api_params` and `permitted` request input declarations.
- Generate request-body schemas and reusable OpenAPI components.
- Add shared type mapping and expanded `ModelSchema` options.
- Use stable resource/action operation IDs and resource tags instead of controller class names.
- Keep generated operation IDs unique across PUT/PATCH and nested route variants.
