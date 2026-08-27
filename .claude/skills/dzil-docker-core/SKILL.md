---
name: dzil-docker-core
description: "Use when working on the Dist-Zilla-Plugin-Docker-API distribution — the plugin's dist.ini attribute surface, the before_build/after_build/release phase hooks, tag template expansion, the API::Docker client adapter, or the Recorder-fake harness under t/lib."
---

# Dist::Zilla::Plugin::Docker::API — architecture and invariants

A Dist::Zilla plugin that builds a Docker image from the built distribution and
pushes it on release. Everything goes through `API::Docker`, which speaks the
Engine HTTP API over a socket — **no `docker` binary is involved anywhere**, so
Podman's rootless socket is a first-class target.

## The four files

```
API.pm          the plugin: Moose, the dist.ini attribute surface, the three
                phase hooks, template variables, git info
  API/Client.pm     the only thing that touches API::Docker (Moo)
  API/TagTemplate.pm  %-expansion (Moo)
  API/Result.pm       value object: image_id, tags, pushed, digest, warnings (Moo)
```

**`API.pm` is Moose, the other three are Moo.** That is forced, not a slip:
`Dist::Zilla::Role::Plugin` is Moose, and the helper classes carry no
Dist::Zilla dependency. `getty-perl-core`'s "one object system per
distribution" yields to the framework here — keep the split on that line and
do not migrate a class across it without a reason.

## The three phases

| Hook | Role | What it does |
|---|---|---|
| `before_build` | `BeforeBuild` | asks the engine for its version and dies there if nothing answers |
| `after_build`  | `AfterBuild`  | builds the image, applies every `tag` locally |
| `release`      | `Releaser`    | re-tags the **already built** image, pushes |

The precheck exists because `after_build` builds unconditionally: without it,
Dist::Zilla gathers, munges and writes a whole distribution and only then dies
on a socket that was never there.

Two environment escapes, and they are not the same:

- `DZIL_DOCKER_API_SKIP_PRECHECK=1` — skip only the version probe. The build
  still runs and still needs an engine.
- `DZIL_DOCKER_API_SKIP=1` — skip the image build entirely for one run.
  `release` **refuses to run** with it set: no build means nothing to push.

## The attribute surface

`tag` is the one canonical tag list, defaults to `['latest', '%V', '%v']`, and
is applied identically in both phases. Setting it in dist.ini **replaces** the
default list, never appends.

Three traps live in the `init_arg`s:

- **`dockerfile` is spelled `file` in dist.ini** (`init_arg => 'file'`). The
  attribute, the reader and the POD all say "dockerfile"; the user writes
  `file = Dockerfile.multi`. `t/15-plugin-defaults.t` is the proof.
- **`_target` and `_network_mode`** are underscore-prefixed so the
  `@Author::GETTY::Docker` bundle can inject them without exposing them in
  user-facing dist.ini. `fail_if_tag_exists` and `skip_latest_on_trial`
  deliberately are **not** hidden. Do not add an underscore prefix unless the
  bundle is the sole writer.
- **`mvp_multivalue_args`** lists every repeatable key
  (`tag build_tag release_tag build_arg label platform`). A new repeatable
  attribute that is not in that list silently keeps only its last value.

Only `build_tag`/`release_tag` are real aliases — `BUILDARGS` merges them into
`tag` with a deprecation warning. See "Known holes" for the ones that only look
like aliases.

## Release re-tags from `tag->[0]`

`release` does not rebuild. It takes `image . ':' . expand($self->tag->[0])` as
the **source** and re-tags every entry of the list onto it. Consequences:

- Reordering the `tag` list changes which image the release re-tags from.
- The source is computed from the *unfiltered* list, so with
  `skip_latest_on_trial` a trial release still re-tags from `image:latest` —
  which exists, because `after_build` does not filter. Correct, but not
  obvious.
- A missing source image surfaces as the engine's own 404 through
  `tag_image`. That is deliberate: no home-grown pre-check was added.

Push failures are collected per tag and reported together in one `log_fatal`;
a tag failure during build only warns and drops that tag.

## Template expansion

`TagTemplate::expand` maps `%n %v %V %t %g %G %b %d %o %a %p` (plus `%vmaj`,
`%vmin`) onto the variables `_template_vars` assembles. Two things to know:

- **An unknown variable expands to the empty string, not an error.** `%q` in a
  tag yields a silently truncated tag. (`_extract_vars` knows the valid set but
  is called from nowhere — dead code, not a safety net.)
- **`%d` (build_root) differs between the phases**: the temporary build
  directory during `after_build`, `$zilla->root` during `release`. Anything
  templated from it will not match across the two.

`%V`/`%vmaj`/`%vmin` are not read from the variable hash at all; they are
derived from `version` inside `_expand_var`.

## The client seam

`client_class` (default `…::API::Client`) is loaded with a runtime
`eval "require"` and constructed with two coderefs, `logger` and
`logger_fatal`, that funnel into the plugin's `log`/`log_fatal`. **This seam is
the entire test strategy** — everything below it is fake-able and nothing in
`API.pm` may reach `API::Docker` directly.

Inside `Client.pm`:

- **`_split_image_ref` exists because the engine's tag endpoint takes repo and
  tag separately** (`POST /images/{name}/tag?repo=&tag=`). Passing a full
  reference as `repo` leaves `tag` empty, the engine appends its own default,
  and podman rejects `example/app:1.0:latest` with a 500 — every version tag
  quietly lost. A colon before the last slash is a registry port, not a tag.
- **A failed build's output rides on the exception, not the event loop.**
  API::Docker croaks on the `errorDetail` event before the caller iterates, so
  the preceding stream is drained from `$err->events` — otherwise a failed
  build logs only its last line.
- **Concise mode is the default.** `_is_build_step_header` recognises the
  legacy builder (`Step N/M :`), Podman's classic builder (`STEP N/M:`) and
  BuildKit (`#N [N/M]`, `#N [name N/M]`). A fourth builder format needs a
  fourth pattern here, plus a case in `t/60-build-progress.t`.
- Registry auth is read from `~/.docker/config.json` (or `$DOCKER_CONFIG`),
  handling `identitytoken`, base64 `auth` and plain user/password, with the
  Docker Hub key aliases spelled out.

## Cross-repo: `../p5-api-docker` owns the wire

`API::Docker` is a Getty distribution in the same workspace and `cpanfile` pins
it (`0.003`). A question about what the daemon accepts or answers — endpoint
shape, event stream, auth header, version gating — is **that** repo's, and gets
a ticket on its board rather than a workaround here. `_split_image_ref` living
here rather than there is a deliberate choice: `API::Docker` mirrors the
endpoint and should keep doing so.

The consumer in the other direction is `@Author::GETTY::Docker` in
`../p5-dist-zilla-pluginbundle-author-getty`, which constructs this plugin
programmatically. Any attribute rename or `init_arg` change is a cross-repo
change — check that bundle still builds.

## Tests — the Recorder fake, never a daemon

`prove -lr t/` must pass on a machine with no engine at all, and does.

Tests drive the real plugin through `Dist::Zilla::Tester->from_config` with an
inline `dist.ini`, and swap the client via `client_class = …::Client::Recorder`
(`t/lib`, reached with `use lib "$Bin/lib"`). The Recorder records every call
into `->calls` and hands back canned results; `…::Client::Unreachable` extends
it and croaks from `engine_info` for the precheck tests.

Consequences worth stating before writing a test:

- **A test that calls `->build` without `client_class` set will reach for a
  real engine.** `t/15-plugin-defaults.t` only inspects attributes, which is
  why it gets away without the fake.
- Assert on what the plugin *sent* (`calls_of('build_image')`, the `tags`,
  `labels` and `buildargs` it passed), not only on what the fake returned — the
  latter proves the fixture.
- `Client.pm`'s own internals (`_split_image_ref`, `_extract_build_lines`,
  `_registry_for_image_ref`, `auth_for_image_ref`) are below the seam and are
  tested by calling them directly, not through the Recorder.
- `t/30-tag-attribute.t` uses `Test::Warnings` to assert the deprecation
  warnings; other files silence them with `local $SIG{__WARN__} = sub {}`.

## Known holes — ticketed, do not fix in passing

- **`remote_tag_exists` returns a hard `0`**, so `fail_if_tag_exists` never
  fires despite being documented as a feature.
- **`repository`, `push` and `load` are not aliases.** They are lazy defaults
  reading *from* the canonical attribute, so setting `load = 0` in dist.ini
  leaves `build_load` at 1 and changes nothing. Only `build_tag`/`release_tag`
  round-trip properly.
- **`Client::build_image`'s `push` branch is dead** — the plugin never passes
  it — and `_push_tags` writes through the `Result` object's hash directly,
  past its read-only attributes.
- **`API.pm` ends without `no Moose;`** before `make_immutable`, against the
  house convention.
