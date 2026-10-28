# Implementation findings

## 2026-10-27 — Route eligibility and cache-policy refactoring

- [x] OAG-REF-001: `SpecBuilder` now has one private `eligible_routes` iterator shared by spec generation, completeness discovery and route introspection. It resolves controllers per call, preserves explicit controller/action exclusions, and opts into ignored JSON mode only when completeness discovery requests it. Mounted paths, action docs, typed path metadata, operation IDs and separate output construction remain unchanged (API-07, API-10, API-12).
- [x] OAG-REF-003: `OpenApiController` now has a private cache-policy wrapper retaining the current configuration, explicit spec/introspection key providers, configured TTL and race-condition TTL. Key providers remain lazy so disabled caching does not fingerprint routes. The existing authorization callback still precedes cache reads/builds, and introspection remains development-only (CORE-04, CORE-09).
- [x] OAG-REF-004, bounded portion: removed unused `SpecBuilder.build_responses` after workspace app/engine/library/tool source searches found only its definition. The live `ResponseBuilder` remains the response owner. Public scaffold classes, layout and asset manifest are retained pending consumer confirmation; this finding is only partially complete.
- Added a common route eligibility matrix exercising missing/non-DSL/plain/configured-base/API/explicit/ignored/action-excluded controllers, hidden-write auditing, mounted typed paths, security overrides and the existing default-response fallback. Added request coverage for cache misses/hits across JSON/YAML, separate introspection keys, TTL/race policy, disabled-cache bypass, authorization after warming and development-only visibility. These tests were written, not run.
- Verification: Ruby 4.0.9 syntax checks pass for all four changed Ruby files; `check_api.py` and `check_tenancy.py` both report zero errors/warnings; `git diff --check` passes. Bundled RuboCop is blocked by missing locked gems, including Puma, SQLite, Propshaft, Minitest and RuboCop. No dependencies installed, application boot, database access or test execution occurred.

## 2026-10-28 Authorized focused regression: OpenAPI generator refactors

Explicitly approved runtime verification passed: 94 tests, 314 assertions, zero failures/errors/skips. Corrected only a test nested stub: outputs already stubs RouteDiscovery.call, so it now runs after the outer audit stub closes. Eligibility, discovery, generation and cache coverage pass.

Command from this project: `env -u DATABASE_URL GEM_HOME=/private/tmp/paxfish-agent-runner-gems GEM_PATH=<own temporary gem home plus shared read-only caches and Ruby 4 gem paths> BUNDLE_FROZEN=true RAILS_ENV=test /Users/jmc/.local/share/mise/installs/ruby/4.0.9/bin/ruby -rbundler/setup -Itest -e 'ARGV.each { |path| require_relative path }' test/route_eligibility_test.rb test/route_discovery_test.rb test/open_api_generator_test.rb test/integration/cache_policy_test.rb`. MCP additionally prepends that Ruby bin directory to PATH. Existing locked dependencies were installed only into the isolated temporary gem home; lockfiles and versions remain unchanged. Rails suites used their own Gemfile and inspected SQLite test configurations, prepared with `ruby -rbundler/setup -S rake app:db:prepare`; UUID uses in-memory SQLite and Logging suites use standalone controlled fixtures. Admin/OpenAPI test corrections pass syntax and target-config Rubocop.


## 2026-10-28 Focused regression verification

User-authorized focused execution results, exact scope, setup-only corrections and environment limits are recorded in the [workspace runtime report](../../../_doc/refactoring/runtime-verification.md). Earlier source-phase statements that tests were unrun are historical. This is targeted coverage, not a full-suite or Gates3/4 production-readiness claim.
