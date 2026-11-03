# gha-workflows

Reusable GitHub Actions workflows ([`workflow_call`][reusing]) for the
[SIMP organization](https://github.com/simp)'s repositories.

Workflow logic that used to be copied into every repo by
[puppetsync](https://github.com/simp/puppetsync) lives here **once**. Each
repo keeps only a thin dispatch shim that calls a workflow in this repo, so
a fix is a tag bump here instead of a fleet-wide sync — and half-rolled-out
changes (like [simp/puppetsync#84][84]) become structurally impossible.
See [simp/puppetsync#85][85] for the background and migration plan.

This repo holds two kinds of workflow, plus shared composite actions:

- **Reusable workflows** (`on: workflow_call`) — called by a thin shim in each
  consuming repo. The original purpose of this repo.
- **Org-level scheduled jobs** (`org_*`) — jobs that run *here* and reach out
  to the org through the API. These have no per-repo shim, because there is
  nothing in the other repos to trigger them. They are the right shape whenever
  a task is fleet-wide and needs no per-repo configuration: one file to change,
  idempotent, and it covers repos outside puppetsync's sync set for free.
- **Composite actions** (`.github/actions/<name>/action.yml`) — steps shared
  across repos that must run inside a job the consuming repo owns, such as
  setting up an acceptance job that has a repo-specific matrix.

[reusing]: https://docs.github.com/en/actions/using-workflows/reusing-workflows
[84]: https://github.com/simp/puppetsync/issues/84
[85]: https://github.com/simp/puppetsync/issues/85

## Workflows

Reusable workflows must live flat in `.github/workflows/`, so files are
namespaced by the kind of repo they serve:

| Prefix | Serves |
|---|---|
| `puppet_*` | Puppet module (`pupmod-*`) repos |
| `rubygem_*` | Ruby gem (`rubygem-*`) repos |
| `rpm_*` | Anything that ships RPMs (shared across repo kinds) |
| `org_*` | Org-level scheduled jobs that run in this repo (not `workflow_call`) |

| Workflow | Purpose |
|---|---|
| [`puppet_create_release_tag.yml`](.github/workflows/puppet_create_release_tag.yml) | Validate `metadata.json`/CHANGELOG and create + push an annotated release tag (triggering the repo's `tag_deploy.yml`) |
| [`org_sync_forks.yml`](.github/workflows/org_sync_forks.yml) | Weekly: fast-forward the org's pure-mirror forks from their upstreams. Skips any fork carrying SIMP commits |
| [`org_reconcile_board_status.yml`](.github/workflows/org_reconcile_board_status.yml) | Hourly: reconcile the [Org Triage board](https://github.com/orgs/simp/projects/11) with live state — Status from member PRs (draft → In Progress, ready → In Review, …), `community` on outside contributions, `needs-attention` on items idle past their column's threshold. Never moves items out of Blocked/Parked/Done, never closes anything |

## Actions

| Action | Purpose |
|---|---|
| [`setup-vagrant-libvirt`](.github/actions/setup-vagrant-libvirt) | Install Vagrant, vagrant-libvirt and libvirt for Beaker acceptance tests from the Actions cache, `ppa:evgeni/vagrant`, or HashiCorp, so a Launchpad outage doesn't fail the job |

Call one as a step, pinned to a release tag like the workflows:

```yaml
      - name: Setup libvirt for Vagrant
        uses: simp/gha-workflows/.github/actions/setup-vagrant-libvirt@v1.1.0
```

## Calling a workflow

Each consuming repo carries a thin shim (maintained by puppetsync) that
forwards its trigger and inputs:

```yaml
name: 'RELENG: Create release tag'

on:
  workflow_dispatch:
    inputs:
      dry_run:
        description: "Dry run (validate + report the tag annotation, don't push)"
        required: false
        type: boolean
        default: false

jobs:
  create-release-tag:
    uses: simp/gha-workflows/.github/workflows/puppet_create_release_tag.yml@v1.0.0
    with:
      dry_run: ${{ inputs.dry_run }}
    secrets: inherit
    permissions:
      contents: write
```

## Versioning

Releases are tagged `vX.Y.Z` (SemVer over the *calling contract*: inputs,
secrets, permissions, and observable behavior). Callers pin an exact tag and
[Renovate](https://github.com/renovatebot/renovate) proposes bumps per repo,
keeping rollouts deliberate and reviewable.

- **Major**: a caller must change (input/secret/permission contract)
- **Minor**: new workflows or actions, or new optional inputs
- **Patch**: behavior fixes within the existing contract

## What belongs here (and what doesn't)

- **Here**: workflow *logic* shared across repos (`on: workflow_call`),
  org-level scheduled jobs that operate on the fleet through the API
  (`org_*`), and composite actions shared across repos
  (`.github/actions/<name>/`). New actions go here rather than in a repo of
  their own, so there is one repo to version, review and protect. Older
  actions still live in their own `simp/github-action-*` repos, e.g.
  [github-action-build-and-sign-pkg-single-rpm](https://github.com/simp/github-action-build-and-sign-pkg-single-rpm).
- **The consuming repo**: triggers, per-repo configuration (matrices,
  nodesets), and anything repo-specific. If a workflow needs per-repo
  variation, model it as inputs — if it can't be, it probably doesn't
  belong here.

## License

[Apache-2.0](LICENSE)
