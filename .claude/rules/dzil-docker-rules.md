# Dist-Zilla-Plugin-Docker-API House Rules

Apply to every task in this distribution unless explicitly overridden. Bias: caution over
speed on non-trivial work; use judgment on trivial tasks. Loaded automatically at launch
(same priority as `CLAUDE.md`). Subagents get their discipline from the skills
force-loaded via `briefing.skills` — this file is for the orchestrating agent.

## Engineering discipline

1. **Think before coding** — state assumptions; when uncertain, ask rather than guess.
   Push back when a simpler approach exists.
2. **Simplicity first** — minimum code that solves the problem. Nothing speculative.
3. **Surgical changes** — touch only what you must. Match existing style.
4. **Goal-driven execution** — define success criteria, loop until verified.
5. **Surface conflicts, don't average them** — pick one (more recent / more tested), flag
   the other for cleanup. Don't blend.
6. **Read before you write** — `Client.pm` is the single seam between the plugin and
   `API::Docker`. A change to what `build_image`/`tag_image`/`push_image` accept or
   return reaches the plugin, the Recorder fake and every phase test at once.
7. **Tests verify intent, not just behavior** — a test that can't fail when the logic
   changes is wrong. Reproduce a bug before fixing it; leave the regression behind.
8. **Checkpoint after every significant step** — summarize: done / verified / left.
9. **Match conventions** — conformance > taste. Surface a harmful convention; don't fork
   silently.
10. **Fail loud** — "Done" is wrong if anything was skipped. "Tests pass" is wrong if any
    were skipped.
11. **A red test is a claim before it is a failure** — before changing code to turn a
    test green, say what the test asserts and whether your fix keeps that claim or
    replaces it. If the claim is wrong, fix the claim and say so.

## Delegation

This rule depends on whether the Agent/Task tool is available to you.

- **You can spawn subagents** (orchestrating main agent): Do NOT touch behavior-relevant
  code yourself — delegate. Your lane: coordinate, inspect, plan, review diffs, run
  tests, manage git, edit non-behavioral docs. When in doubt, delegate. Why: only the
  `dzil-docker-*` agents get their skills force-loaded via `briefing.skills`; you get no
  briefing and would touch internals with too little context.

  | Task | Agent |
  |---|---|
  | Implement / refactor / debug the plugin, the client adapter, cpanfile | `dzil-docker-worker` (default) |
  | Write/extend tests | `dzil-docker-test-writer` |
  | Pre-release audit | `dzil-docker-release-checker` |
  | POD and README | `dzil-docker-doc-writer` |

  A question about what the Docker daemon itself accepts or answers is not this repo's —
  it belongs to `../p5-api-docker` and its `api-docker-engine-worker`, as a ticket on
  that repo's board.

- **You cannot spawn subagents** (you ARE a `dzil-docker-*` agent): the delegation lock
  does not apply to you — implement, refactor, debug and test per these rules.

Behavior-relevant = the phase hooks, the dist.ini attribute surface and its `init_arg`s,
tag template expansion, `Client.pm` and everything it returns, `cpanfile`, and tests.
Pure prose docs and `Changes` notes are not.

## Coordination — karr board (always in scope)

Ticket coordination is the orchestrating agent's job, so `karr` is always in scope —
don't invoke the `kanban-issues-karr-cli` skill first, just use it. Git-native kanban;
state lives in `refs/karr/*`; one board, this repo. Day-to-day: `karr list --compact` /
`karr board` for open work; `karr show ID` for detail; `karr create/edit/move/handoff`
for the usual flow; mutating commands auto-sync. Full surface: skill
`kanban-issues-karr-cli`.

Cross-repo work is a ticket on the *other* repo's board (`cd ../p5-api-docker && karr
create …`), never a direct edit there.

**Serialize board mutations when fanning out.** Keep implementation parallel if you like,
but collect results and loop `karr move`/`handoff`/`sync` sequentially — N landing at
once is a resource event, not a cheap command.

## Release — never without permission

`dzil build`, `dzil test` and `prove -lr t/` are fine anytime. `dzil release` and any
CPAN upload are STRICTLY forbidden without the maintainer's explicit go-ahead — even if
`Changes` or a plan names "release" as the next step. For anything heading toward
release: stop and ask. **This dist depends on `API::Docker`, which is Getty's own and may
be pinned to a version CPAN does not have yet — it cannot ship before that one does.**

## Public issues — never act without instruction

Two trackers, two universes. **karr** is the internal agent work board, churned freely.
**GitHub issues on `Getty/p5-dist-zilla-plugin-docker-api`** and CPAN RT carry real
humans' reports under the maintainer's name. **Never act on a public issue on your own
initiative — not even to read it.** No listing, viewing, commenting, editing, closing or
creating unless the user names a specific item to handle.

## Repo-specific hazards

- **This plugin is not applied to its own distribution.** `dist.ini` here contains only
  `[@Author::GETTY]`, so `dzil build` in this repo builds no image and exercises no
  phase hook. Every check of real plugin behavior goes through the test suite or a
  throwaway dist — never assume a green `dzil build` here proved anything about Docker.
- **There is no Docker on this machine — only rootless Podman** at
  `unix:///run/user/1000/podman/podman.sock`. `/var/run/docker.sock` does not exist, and
  that is the only fallback the plugin has, so anything live needs `DOCKER_HOST` set
  explicitly.
- **`fail_if_tag_exists` asks the *registry*, not the local daemon.** It runs through
  `API::Docker`'s `distribution->exists` (`GET /distribution/{name}/json`) — real since
  API::Docker 0.004 (it was previously a stub that always answered `no`). Rootless
  Podman has no `/distribution` route, so there the lookup croaks and the release
  aborts rather than silently treating the tag as free. The POD and `README.md`
  describe this. Don't try to answer the question from the local daemon.
- **An unknown dist.ini key is silently discarded, not rejected.** That is how
  `dockerfile = ...` went unnoticed for so long: the attribute carried
  `init_arg => 'file'`, so the documented key fell through to the default with no
  error. Before documenting or changing any attribute, read its `init_arg` — that is
  the key users write, and this distribution's whole user surface is dist.ini keys.
- **Deprecated spellings live in `BUILDARGS` only.** The `%DEPRECATED_KEY` table plus
  `init_arg => undef` on the deprecated readers is what makes them work at all; an
  alias declared as a lazy attribute reading *from* the canonical one silently does
  nothing, which is exactly what `repository`, `push` and `load` used to do.
- **`release` re-tags from `tag->[0]`, it does not rebuild.** Reordering the `tag` list
  silently changes which image a release ships. Anything touching the tag list is a
  release-behavior change.
- **An unknown `%` variable in a tag template expands to the empty string, not an
  error.** A typo produces a truncated tag and a successful build. Verify template
  changes against `t/10-tag-template.t`, not by eye.
- **`../p5-dist-zilla-pluginbundle-author-getty` constructs this plugin
  programmatically.** An attribute or `init_arg` rename is a coordinated change: verify
  that bundle, or file a ticket on its board before landing.

## Perl specifics — reference, don't restate

Module loading, `$VERSION`, cpanfile pinning and house style: skills `getty-perl-core`,
`getty-perl-moose` (the plugin class), `getty-perl-moo` (the three helper classes).
`[@Author::GETTY]`, POD weaving, `{{$NEXT}}`: skill `getty-perl-release-author-getty`.
dist.ini mechanics: `perl-release-dist-ini`. Commit messages: `getty-git-commit-style`.
Architecture, phase hooks and the client seam: `dzil-docker-core`. Don't duplicate any of
it here.
