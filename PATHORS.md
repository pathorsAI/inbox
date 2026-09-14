# Pathors Inbox — this repository

`pathorsAI/inbox` is the source of the **Pathors Inbox** white-label build of
Chatwoot. It started life as a GitHub fork of `chatwoot/chatwoot` and left the
fork network on 2026-09-14 (pathorsAI/pathors#2829) so it could be private and
so PRs default to *this* repo instead of upstream. Everything below is what
differs from a stock Chatwoot checkout; for Chatwoot itself, see the upstream
[README](./README.md).

## Branches

| Branch | Role |
|---|---|
| `develop` | trunk. Every merge here publishes the production image (see *Deploy*) |
| `master` | unused — kept only so upstream's release tooling does not trip on its absence |
| `chore/sync-upstream-YYYY-MM` | one branch per upstream sync, merged by PR |

Upstream is tracked on developer machines, not on GitHub:

```bash
git remote add upstream https://github.com/chatwoot/chatwoot.git   # once
git fetch upstream
git switch -c chore/sync-upstream-$(date +%Y-%m) develop
git merge upstream/develop          # resolve, run specs, open a PR against develop
```

Our own commits sit on top of upstream `develop`; a sync is a plain merge, not a
rebase, so `git log upstream/develop..develop` always lists exactly what is
ours. Keep it that way — a rebase rewrites the PR history this repo carries.

## What we changed

The Pathors-specific work is the feature set, not a patch on top: voice inboxes
whose phone number is bound to a Pathors agent (#23, #28, #41, #52), the Pathors
integration card and SSO deep links (#24, #27), tickets and the help-center
portal (#9, #32, #38), outbound campaigns (#22), inbound email triage (#29, #34),
zh-TW locales, and the enterprise-code strip that makes the image a CE build we
may run commercially (#51). `git log upstream/develop..develop` is the
authoritative list.

## CI

| Workflow | Runner | Notes |
|---|---|---|
| `sonar.yml` | self-hosted `gke` (org-level, pathors-tw) | SonarQube at https://sonar.pathors.com, project `pathorsAI_inbox`. New-code gate; the full-project baseline is upstream's |
| `publish_foss_docker.yml` | GitHub-hosted, amd64 only | publishes `ghcr.io/pathorsai/pathors-inbox:<branch>-ce` on push to `develop`/`master` and tags |
| `test_docker_build.yml` | GitHub-hosted, amd64 only | PR-time Dockerfile check |
| `run_foss_spec.yml`, `frontend-fe.yml`, `size-limit.yml`, `run_mfa_spec.yml` | GitHub-hosted | upstream's suites, unchanged |
| `claude.yml`, `claude-code-review.yml` | GitHub-hosted | `@claude` and automatic PR review |

**Private repos get the smaller GitHub-hosted runner** — 2 vCPU / 7 GB instead of
the 4 vCPU / 16 GB a public repo gets. Node sizes its default heap from system
memory, so the Vite build (both `assets:precompile` and the in-process
`autoBuild` that the first page-rendering spec triggers in the test env) OOMs at
~2 GB unless `NODE_OPTIONS=--max-old-space-size=4096` is set. The three workflows
that build the frontend carry that flag; a new one must too, or every controller
spec 500s with "Vite Ruby can't find entrypoints/… in the manifests".

arm64 was dropped from both Docker workflows on purpose: the only consumer
(GKE) is amd64, and a private repository has no GitHub-hosted arm runner —
`ubuntu-22.04-arm` would queue forever.

Upstream's community-management bots (`lock.yml`, `stale.yml`,
`logging_percentage_check.yml`) are disabled in the Actions UI rather than
deleted, so upstream syncs do not conflict on them.

Moving the Docker workflows to self-hosted runners requires the `docker`-labelled
machines (NCHC ×4, arch447 ×2) to be registered at **org** level; today they are
registered to `pathorsAI/pathors` only. Once that is done, flip `runs-on` to
`[self-hosted, docker]` — tracked in pathorsAI/pathors#2829.

## Deploy

Nothing here deploys. The chain is:

1. merge to `develop` → `publish_foss_docker.yml` pushes the image and moves the
   `develop-ce` tag
2. `pathorsAI/pathors` `.github/workflows/chatwoot-digest-writeback.yml` polls
   that tag every 15 minutes and, when it moves, writes the new digest into
   `infra/k8s/chatwoot/20-chatwoot.yaml` + `30-migrate-job.yaml` on `main`
3. ArgoCD (`pathors-tw`) auto-syncs the Deployment

So a merge is live within ~20 minutes, with no human step — **except** DB
migrations: `30-migrate-job.yaml` is excluded from ArgoCD and must be applied by
hand (`kubectl apply`) when a release carries one. Runbook:
`pathorsAI/pathors` → `engineering/chatwoot-hosting.md`.

The GHCR package `pathors-inbox` is private and grants `pathorsAI/pathors` read
access (Package settings → Manage Actions access). That grant is by repository
id and survived the rename.

## Local development

- Node 24 + pnpm 10, Ruby per `.ruby-version`. A `pnpm install` under the wrong
  Node version leaves an empty `node_modules` without erroring.
- Nested git worktrees under `.claude/worktrees/` are supported by the eslint /
  vitest config (#25).
