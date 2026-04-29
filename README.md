# Dist::Zilla::Plugin::Docker::API

Builds and publishes Docker images as release artifacts using the Docker Engine API.

## Why this plugin?

When releasing a Perl distribution, you often want to ship a Docker image containing your application. This plugin integrates Docker image builds directly into the Dist::Zilla release workflow:

- **No CLI dependency** — Uses L<API::Docker> for direct API communication
- **No shell quoting bugs** — All parameters passed as structured data
- **Streaming progress** — Real-time Docker build output via callbacks
- **Template expansion** — Build args and labels use Dist::Zilla template variables

## Installation

```bash
cpanm Dist::Zilla::Plugin::Docker::API
```

Or with Dist::Zilla itself:

```bash
dzil install
```

## Quick Start

### Local development build

Add to your `dist.ini`:

```ini
[Docker::API / local]
phase      = build
repository = localhost:5000/my-app
context    = build
file       = Dockerfile

tag = latest
tag = test-%v
push = 0
load = 1
```

Run `dzil build` — after the distribution is built, a Docker image is created from the build directory.

### Release with registry push

```ini
[Docker::API / release]
phase      = release
repository = ghcr.io/myuser/my-app
context    = archive

tag = %v
tag = v%v
tag = latest

push        = 1
fail_if_tag_exists = 1
skip_latest_on_trial = 1
```

Run `dzil release` — the release tarball becomes the Docker build context, and images are pushed to the registry.

## Phase semantics

| Phase | When it runs | Default push | Default context |
|-------|--------------|--------------|-----------------|
| `build` | After `dzil build` | `0` (local only) | `build` (build_root) |
| `release` | During `dzil release` | `1` (to registry) | `archive` (tarball) |
| `after_release` | After `dzil release` | (inherited) | (inherited) |

## Configuration reference

### Required

```ini
repository = ghcr.io/user/repo    # Full image repository name
```

### Common options

```ini
phase      = build               # When to run: build, release, after_release
context    = build              # Context mode: build, source, archive
file       = Dockerfile         # Dockerfile name (in context root)
load       = 1                  # Load image into local Docker daemon
push       = 0                  # Push to remote registry
pull       = 0                  # Always pull base image
no_cache   = 0                  # Don't use Docker cache
rm         = 1                  # Remove intermediate containers
force_rm   = 1                  # Always remove intermediate containers
```

### Tag templates

Tags are expanded via L<Dist::Zilla::Plugin::Docker::API::TagTemplate>:

```ini
tag = latest                    # Static tag
tag = %v                        # Version number
tag = v%v                       # Prefixed version
tag = build-%v-%g              # With git short SHA
tag = %b-%g                     # Branch and SHA
```

| Variable | Description | Example |
|----------|-------------|---------|
| `%n` | Distribution name | `My-App` |
| `%v` | Distribution version | `1.234` |
| `%t` | Trial suffix | `-TRIAL` or empty |
| `%g` | Short git SHA (7 chars) | `a1b2c3d` |
| `%G` | Full git SHA (40 chars) | `a1b2c3d4e5f6...` |
| `%b` | Git branch name | `main` |
| `%d` | Dist::Zilla build root | `/path/to/build` |
| `%o` | Source/root directory | `/path/to/repo` |
| `%a` | Release archive path | `/path/to/archive.tar.gz` |
| `%p` | Plugin instance name | `Docker::API` |

### Build arguments

Template-enabled build arguments:

```ini
build_arg = DIST_NAME=%n
build_arg = DIST_VERSION=%v
build_arg = MCP_WIKI_VERSION=%v
```

### OCI labels

Template-enabled labels following OCI image specification:

```ini
label = org.opencontainers.image.title=%n
label = org.opencontainers.image.version=%v
label = org.opencontainers.image.description=Perl distribution %n v%v
```

### Registry and auth

The plugin uses the Docker daemon's configured registries. For pushing:

- Ensure `docker login` has been run for your registry
- Or set `DOCKER_AUTH_CONFIG` environment variable with JSON config

### Tag existence check

Fail fast if a tag already exists on the remote:

```ini
fail_if_tag_exists = 1
```

Skip `latest` tag for trial releases:

```ini
skip_latest_on_trial = 1
```

## Context modes

| Mode | Description | Use case |
|------|-------------|----------|
| `build` | Tar of Dist::Zilla's build_root | Local development |
| `source` | Tar of the source repository | Building from git |
| `archive` | The release tarball | Reproducible releases |

## Result object

After building, a L<Dist::Zilla::Plugin::Docker::API::Result> object is returned:

```perl
my $result = $plugin->client->build_image(...);
# $result->image_id   # Docker image ID
# $result->tags       # ArrayRef of applied tags
# $result->pushed      # ArrayRef of successfully pushed tags
# $result->digest      # SHA256 digest of pushed image
# $result->warnings    # ArrayRef of non-fatal errors
```

## Example: MCP-Wiki

The L<MCP::Wiki> distribution uses this plugin for its Docker images:

```ini
; Test the Docker::API plugin - local build phase
[Docker::API / local]
phase      = build
repository = localhost:5000/mcp-wiki
context    = build
file       = Dockerfile

tag = latest
tag = test-%v
push = 0
load = 1
load = 1
```

See L<MCP::Wiki> for a complete example with multi-stage Dockerfile.

## Architecture

### Helper classes

- L<Dist::Zilla::Plugin::Docker::API::Config> — Validated configuration
- L<Dist::Zilla::Plugin::Docker::API::TagTemplate> — Template variable expansion
- L<Dist::Zilla::Plugin::Docker::API::Context> — Build context resolver
- L<Dist::Zilla::Plugin::Docker::API::Client> — API::Docker adapter
- L<Dist::Zilla::Plugin::Docker::API::Result> — Build/push result

### Roles consumed

- L<Dist::Zilla::Role::Plugin>
- L<Dist::Zilla::Role::AfterBuild>
- L<Dist::Zilla::Role::BeforeRelease>
- L<Dist::Zilla::Role::Releaser>
- L<Dist::Zilla::Role::AfterRelease>

## See also

- L<API::Docker> — Perl client for Docker Engine API
- L<Dist::Zilla> — CPAN distribution builder
- L<Dist::Zilla::Role::AfterBuild>
- L<Dist::Zilla::Role::Releaser>

## License

Copyright (c) 2026 Torsten Raudssus L<https://raudssus.de/>.

This is free software; you can redistribute it and/or modify it under the same terms as Perl 5 itself.