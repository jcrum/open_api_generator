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
- Follow-up: enable `Core::OpenApi.operator_session_authorizer` in pfos once its in-progress
  work lands (pfos was not touched in this batch).

## 0.2.0 - 2026-08-14

- Add `api_params` and `permitted` request input declarations.
- Generate request-body schemas and reusable OpenAPI components.
- Add shared type mapping and expanded `ModelSchema` options.
- Use stable resource/action operation IDs and resource tags instead of controller class names.
- Keep generated operation IDs unique across PUT/PATCH and nested route variants.
