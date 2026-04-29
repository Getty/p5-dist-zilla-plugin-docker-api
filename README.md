# Dist::Zilla Plugin Docker API

Builds and publishes Docker images as release artifacts using the Docker Engine API.

## Why API::Docker?

- No dependency on Docker CLI binary
- No shell quoting bugs around tags, build args, paths, auth headers
- Easier unit tests with fake Docker client
- Structured Docker progress events via streaming API
- Build errors become `log_fatal` with useful context

## Phase semantics

### `phase = build`

Runs after `dzil build`. Default for local development:

```ini
[Docker::API]
phase      = build
repository = ghcr.io/example/my-app
context    = build
file       = Dockerfile

tag = latest
tag = build-%v
push = 0
load = 1
```

### `phase = release`

Runs during `dzil release`. Default for publishing:

```ini
[Docker::API / release]
phase      = release
repository = ghcr.io/example/my-app
context    = archive
file       = Dockerfile

tag = %v
tag = v%v
tag = latest

push = 1
fail_if_tag_exists = 1
skip_latest_on_trial = 1
```

## Tag templates

| Variable | Description | Example |
|----------|-------------|---------|
| `%n` | Distribution name | `My-App` |
| `%v` | Distribution version | `1.234` |
| `%t` | Trial suffix | `-TRIAL` or empty |
| `%g` | Short git SHA | `a1b2c3d` |
| `%G` | Full git SHA | `a1b2c3d4e5f6...` |
| `%b` | Git branch | `main` |
| `%d` | Dist::Zilla build root | `/path/to/build` |
| `%o` | Source/root directory | `/path/to/repo` |
| `%a` | Release archive path | `/path/to/archive.tar.gz` |
| `%p` | Plugin name | `Docker::API` |

## Context modes

| Mode | Description |
|------|-------------|
| `build` | Tar stream of build_root (default for phase=build) |
| `source` | Tar stream of zilla root |
| `archive` | Release tarball (default for phase=release) |

## Build args and labels

```ini
build_arg = DIST_NAME=%n
build_arg = DIST_VERSION=%v
label = org.opencontainers.image.title=%n
label = org.opencontainers.image.version=%v
```

## Install

```bash
cpanm Dist::Zilla::Plugin::Docker::API
```

Or with Dist::Zilla:

```bash
dzil install
```

## License

Copyright (c) 2026 Torsten Raudssus. Same terms as Perl 5 itself.