# Dist::Zilla::Plugin::Docker::API

Build and publish Docker images as Dist::Zilla release artifacts using
[API::Docker](https://metacpan.org/pod/API::Docker) — no `docker` CLI shell-outs.

## Why this plugin?

When releasing a Perl distribution, you often want to ship a Docker image
alongside it. This plugin integrates the image build directly into the
Dist::Zilla `build` / `release` workflow:

- **No CLI dependency** — uses `API::Docker` to talk to the Docker daemon directly.
- **No shell quoting bugs** — all parameters passed as structured data.
- **Streaming progress** — real-time Docker build output via callbacks.
- **Template expansion** — tags, build args and labels use Dist::Zilla template
  variables (`%v`, `%n`, `%g`, ...).

## Installation

```bash
cpanm Dist::Zilla::Plugin::Docker::API
```

## Quick start

```ini
[Docker::API]
image      = ghcr.io/example/my-app
dockerfile = Dockerfile

tag = latest
tag = %v
```

- `dzil build` builds the image and applies every `tag` locally.
- `dzil release` re-tags the already-built image and (by default) pushes it.

The same `tag` list is used in both phases — there is no separate
build-vs-release list.

## Behavior

| Dzil command   | Docker behavior |
|----------------|-----------------|
| `dzil build`   | Build image, apply every `tag`, load into local daemon (if `build_load=1`). No push. |
| `dzil release` | Re-tag the already-built image with every `tag`, push (if `release_push=1`), load (if `release_load=1`). |

## Container engine

Builds and pushes go through [`API::Docker`](https://metacpan.org/pod/API::Docker),
which speaks the Docker Engine HTTP API over a socket. No `docker` binary is
involved at any point, so any engine serving that API will do and Docker itself
need not be installed. Podman's rootless socket is a tested alternative:

```bash
systemctl --user enable --now podman.socket
export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
```

The socket is located from `DOCKER_HOST`, falling back to
`/var/run/docker.sock` and nothing else — Docker contexts are *not* consulted,
so a daemon picked with `docker context use` will not be found. `target`
reaches the engine unchanged, so multi-stage builds behave the same either way.

Since `after_build` builds an image unconditionally, the plugin verifies in
`before_build` that an engine actually answers, and gives up there instead of
after a whole distribution has been assembled:

```
[Docker::API] Docker::API engine ready: Podman Engine 5.4.2 (API 1.41)
```

| Variable | Effect |
|---|---|
| `DOCKER_HOST` | Socket or URL of the engine to talk to |
| `DZIL_DOCKER_API_SKIP_PRECHECK=1` | Skip the startup check; an unreachable engine then only surfaces at image build time |

## Configuration

### Required

- `image` — full image repository name, e.g. `ghcr.io/user/my-app`.

### Tags

`tag` is multi-value and template-enabled. Default is `latest` plus `%v`.

```ini
tag = latest
tag = %v
tag = v%v
tag = build-%v-%g
```

Available template variables:

| Variable | Description                       | Example          |
|----------|-----------------------------------|------------------|
| `%n`     | Distribution name                 | `My-App`         |
| `%v`     | Distribution version              | `1.234`          |
| `%t`     | Trial suffix                      | `-TRIAL` or empty|
| `%g`     | Short git SHA (7 chars)           | `a1b2c3d`        |
| `%G`     | Full git SHA (40 chars)           | `a1b2c3d4e5f6...`|
| `%b`     | Git branch name                   | `main`           |
| `%d`     | Dist::Zilla build root            | `/path/to/build` |
| `%o`     | Source repository root            | `/path/to/repo`  |
| `%a`     | Release archive path              | `/path/to/x.tgz` |
| `%p`     | Plugin instance name              | `Docker::API`    |

### Build/release switches

```ini
build_load   = 1     # load built image into local daemon (default: 1)
release_push = 1     # push during release (default: 1)
release_load = 0     # also load during release (default: 0)
```

### Build options

```ini
dockerfile = Dockerfile     # name of the Dockerfile in the build root
pull       = 0
no_cache   = 0
rm         = 1
force_rm   = 1
platform   = linux/amd64    # multi-value
```

| Context mode | Description                          |
|--------------|--------------------------------------|
| `build`      | Tar of Dist::Zilla's build_root      |
| `source`     | Tar of the source repository         |
| `archive`    | The release tarball                  |

### Build args and labels

Both `build_arg` and `label` are multi-value and template-enabled
(`KEY=VALUE` form).

```ini
build_arg = DIST_NAME=%n
build_arg = DIST_VERSION=%v

label = org.opencontainers.image.title=%n
label = org.opencontainers.image.version=%v
```

### Tag-exists check and trials

```ini
fail_if_tag_exists   = 1     # NOT IMPLEMENTED YET - see below
skip_latest_on_trial = 1     # omit `latest` for trial releases (default: 1)
```

`fail_if_tag_exists` is accepted and consulted during release, but the registry
lookup behind it is still a stub that always answers "no", so the check never
fires. Do not rely on it to protect an existing tag.

### Registry auth

The plugin uses the Docker daemon's configured registries:

- Run `docker login` for your registry, or
- Set `DOCKER_AUTH_CONFIG` with a JSON config.

## Use via `@Author::GETTY`

In a distribution that uses
[@Author::GETTY](https://metacpan.org/pod/Dist::Zilla::PluginBundle::Author::GETTY),
the bundle exposes a subsection that constructs a `Docker::API` plugin per
occurrence:

```ini
[@Author::GETTY]
docker_image = registry/app
docker_tags  = latest %v

[@Author::GETTY::Docker / runtime-root]
target = runtime-root

[@Author::GETTY::Docker / runtime-user]
target = runtime-user
tags   = user
local  = 1
```

See the bundle docs for the full inheritance model.

## Deprecated options

The following config keys still work but emit a deprecation warning:

| Deprecated      | Replacement       |
|-----------------|-------------------|
| `build_tag`     | `tag`             |
| `release_tag`   | `tag`             |
| `repository`    | `image`           |
| `phase`         | (no longer used)  |
| `push`          | `release_push`    |
| `load`          | `build_load`      |

When `build_tag` and/or `release_tag` are given, their values are merged
(build first, then release) into `tag`. If `tag` is also set explicitly,
it wins and the legacy values are ignored.

## Result object

`build_image` returns a `Dist::Zilla::Plugin::Docker::API::Result`:

```perl
my $result = $plugin->client->build_image(...);
$result->image_id;   # Docker image ID
$result->tags;       # ArrayRef of applied tags
$result->pushed;     # ArrayRef of successfully pushed tags
$result->digest;     # SHA256 digest of pushed image
$result->warnings;   # ArrayRef of non-fatal errors
```

## Architecture

Helper classes:

- `Dist::Zilla::Plugin::Docker::API::TagTemplate` — template variable expansion
- `Dist::Zilla::Plugin::Docker::API::Client` — `API::Docker` adapter
- `Dist::Zilla::Plugin::Docker::API::Result` — build/push result

Roles consumed:

- `Dist::Zilla::Role::Plugin`
- `Dist::Zilla::Role::AfterBuild`
- `Dist::Zilla::Role::Releaser`

## See also

- [API::Docker](https://metacpan.org/pod/API::Docker)
- [Dist::Zilla](https://metacpan.org/pod/Dist::Zilla)
- [Dist::Zilla::PluginBundle::Author::GETTY](https://metacpan.org/pod/Dist::Zilla::PluginBundle::Author::GETTY)

## License

Copyright (c) 2026 Torsten Raudssus <https://raudssus.de/>.

This is free software; you can redistribute it and/or modify it under the
same terms as Perl 5 itself.
