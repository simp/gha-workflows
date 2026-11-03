# setup-vagrant-libvirt

Install Vagrant, the vagrant-libvirt provider and libvirt on an Ubuntu
GitHub Actions runner, for Beaker acceptance tests with
`BEAKER_HYPERVISOR=vagrant_libvirt`.

Ubuntu stopped shipping `vagrant` and `vagrant-libvirt` after 23.10.
[`ppa:evgeni/vagrant`](https://launchpad.net/~evgeni/+archive/ubuntu/vagrant)
packages Vagrant 2.3.7 (the last MPL-licensed release) and a matching
vagrant-libvirt. Installing from the PPA alone fails the job whenever
Launchpad is down, so this action tries each source in turn:

1. **The Actions cache**: the PPA's packages (including any dependencies
   the PPA supplies), saved by a `cache-only` run on the default branch.
   This path makes no requests to Launchpad; everything else comes from
   the Ubuntu archive.
2. **The PPA**: add it, refresh only its index (so an error from that
   source fails the attempt rather than being a warning), and install.
   Each step is tried three times, 30s and then 60s apart.
3. **HashiCorp**: `vagrant` (pinned to `vagrant-version`) from
   <https://apt.releases.hashicorp.com>, plus `vagrant plugin install
   vagrant-libvirt` (pinned to `vagrant-libvirt-version`), built against
   `libvirt-dev`. HashiCorp's Vagrant is BSL-licensed, so the action emits
   a warning when it falls back to it.

### Which runner

The cache and the PPA only apply on the Ubuntu series in `ppa-series`. The
PPA publishes for `noble` alone, so they need `runs-on: ubuntu-24.04`. On
any other series the action goes straight to HashiCorp, with a notice
rather than a warning. `ubuntu-latest` now resolves to `ubuntu-26.04`
(`resolute`), so a job on `ubuntu-latest` always installs HashiCorp's
Vagrant and never contacts Launchpad, and the cache below is only a
hedge for jobs on `ubuntu-24.04`.

## Usage

In the acceptance job:

```yaml
      - name: Setup libvirt for Vagrant
        uses: simp/gha-workflows/.github/actions/setup-vagrant-libvirt@v1.1.0
      - name: beaker
        env:
          BEAKER_HYPERVISOR: 'vagrant_libvirt'
          VAGRANT_DEFAULT_PROVIDER: 'libvirt'
        run: bundle exec rake beaker:suites[default,almalinux9]
```

### Warming the cache

**The cache only helps pull requests if the default branch fills it.**
A pull request can restore caches saved from its own ref, its base branch
or the default branch, but not caches saved by other pull requests. Add a
separate workflow that runs this action with `cache-only: 'true'` on the
default branch, on a runner whose Ubuntu series the PPA publishes for:

```yaml
name: Vagrant package cache

'on':
  push:
    branches: [main]
  schedule:
    - cron: '17 6 * * 1,4'
  workflow_dispatch: {}

jobs:
  cache:
    runs-on: ubuntu-24.04
    steps:
      - uses: simp/gha-workflows/.github/actions/setup-vagrant-libvirt@v1.1.0
        with:
          cache-only: 'true'
```

A `cache-only` run asks apt which packages the PPA would currently supply
and derives the cache key from their file names. If an entry with that key
already exists, the run restores it, which resets GitHub's seven-day
eviction clock. Otherwise it downloads the packages and saves a new entry.
A new PPA build therefore gets a new key, and installs restore the newest
key for their Ubuntu series and architecture. The run fails if the PPA is
still unreachable after the retries, so an outage shows up in the
scheduled run.

GitHub disables scheduled workflows in public repos after 60 days without
activity, so on a quiet repo the cache can expire and the next pull
request starts cold.

## Inputs

| Input | Default | Description |
|---|---|---|
| `cache-only` | `'false'` | `'true'` saves the PPA's packages to the Actions cache instead of installing anything |
| `cache` | `'true'` | `'false'` ignores the Actions cache when installing |
| `ppa-series` | `'noble'` | Space-separated Ubuntu codenames the PPA publishes for |
| `vagrant-version` | `'2.4.9-1'` | HashiCorp's apt version of `vagrant`, for the fallback |
| `vagrant-libvirt-version` | `'0.12.2'` | The `vagrant-libvirt` plugin version for the fallback |

## Outputs

| Output | Description |
|---|---|
| `source` | Install: `cache`, `ppa` or `hashicorp`. Cache-only: `cached` (already cached), `saved`, or `none` (the PPA doesn't publish for this series) |
