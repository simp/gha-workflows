#!/bin/bash
#
# The steps of action.yml. Usage: setup-vagrant-libvirt.bash COMMAND
#
#   series    report the Ubuntu codename, whether the PPA publishes for it,
#             and the cache directory and key prefix
#   install   install Vagrant, vagrant-libvirt and libvirt from the cached
#             PPA packages, else the PPA, else HashiCorp and rubygems.org
#   resolve   add the PPA and name the packages it would install, with a
#             cache key derived from their file names
#   download  download the resolved packages into the cache directory
#             (run in the same job as resolve, which adds the PPA)
#
# ppa:evgeni/vagrant has vagrant 2.3.7, the last MPL-licensed release, and
# a matching vagrant-libvirt. Ubuntu dropped both after 23.10.

set -euo pipefail

PPA_NAME='ppa:evgeni/vagrant'
PPA_URL='https://ppa.launchpadcontent.net/evgeni/vagrant/'
PPA_LIST="${RUNNER_TEMP:-/tmp}/vagrant-ppa-debs.list"
LIBVIRT_PACKAGES=(libvirt-daemon-system libvirt-daemon qemu-system-x86 qemu-utils dnsmasq)

# Up to three attempts, 30s and then 60s apart
retry() {
  local delay
  for delay in 30 60 0; do
    "$@" && return 0
    if [ "$delay" -eq 0 ]; then
      return 1
    fi
    echo "::notice::Retrying in ${delay}s: $*"
    sleep "$delay"
  done
}

ppa_sources() {
  compgen -G '/etc/apt/sources.list.d/evgeni-ubuntu-vagrant-*' || true
}

# Refresh the PPA's index alone, failing on any error. A plain
# `apt-get update` only warns when a source is unreachable.
update_ppa() {
  local sources
  sources=$(ppa_sources)
  [ -n "$sources" ] || return 1
  sudo apt-get update --error-on=any \
    -o Dir::Etc::sourcelist="$sources" \
    -o Dir::Etc::sourceparts=- \
    -o APT::Get::List-Cleanup=0
}

add_ppa() {
  retry sudo add-apt-repository -y -n "$PPA_NAME" && retry update_ppa
}

# Removing the PPA with add-apt-repository can itself need Launchpad
remove_ppa() {
  sudo rm -f /etc/apt/sources.list.d/evgeni-ubuntu-vagrant-*
}

series() {
  local ppa=false arch s
  # shellcheck source=/dev/null
  . /etc/os-release
  arch=$(dpkg --print-architecture)
  for s in ${PPA_SERIES:-}; do
    if [ "$s" = "$VERSION_CODENAME" ]; then
      ppa=true
    fi
  done
  {
    echo "codename=${VERSION_CODENAME}"
    echo "ppa=${ppa}"
    echo "dir=${RUNNER_TEMP}/vagrant-ppa-debs"
    echo "prefix=vagrant-ppa-debs-${VERSION_CODENAME}-${arch}-"
  } >> "$GITHUB_OUTPUT"
}

from_cache() {
  if ! compgen -G "${DEBS}/*.deb" > /dev/null; then
    return 1
  fi
  echo "Installing the cached PPA packages: $(cd "$DEBS" && echo *.deb)"
  if retry sudo apt-get update &&
    retry sudo apt-get install -y --no-install-recommends "$DEBS"/*.deb "${LIBVIRT_PACKAGES[@]}"; then
    return 0
  fi
  echo '::warning::Installing the cached PPA packages failed; trying the PPA'
  return 1
}

from_ppa() {
  if [ "${PPA:-}" != 'true' ]; then
    return 1
  fi
  retry sudo apt-get update || true
  if add_ppa && retry sudo apt-get install -y --no-install-recommends vagrant vagrant-libvirt "${LIBVIRT_PACKAGES[@]}"; then
    return 0
  fi
  remove_ppa
  return 1
}

from_hashicorp() {
  local fallback="BSL-licensed Vagrant ${VAGRANT_VERSION} from HashiCorp and vagrant-libvirt ${VAGRANT_LIBVIRT_VERSION} from rubygems.org"
  if [ "${PPA:-}" = 'true' ]; then
    echo "::warning::ppa:evgeni/vagrant is unavailable, so this job uses ${fallback}"
  else
    echo "::notice::ppa:evgeni/vagrant has no packages for Ubuntu ${CODENAME}, so this job uses ${fallback}"
  fi
  retry curl -fsSL -o "${RUNNER_TEMP}/hashicorp.asc" https://apt.releases.hashicorp.com/gpg
  sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg "${RUNNER_TEMP}/hashicorp.asc"
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${CODENAME} main" |
    sudo tee /etc/apt/sources.list.d/hashicorp.list
  retry sudo apt-get update
  retry sudo apt-get install -y --no-install-recommends "vagrant=${VAGRANT_VERSION}" \
    libvirt-dev build-essential pkg-config "${LIBVIRT_PACKAGES[@]}"
  retry vagrant plugin install vagrant-libvirt --plugin-version "$VAGRANT_LIBVIRT_VERSION"
}

install() {
  local source
  if from_cache; then
    source=cache
  elif from_ppa; then
    source=ppa
  else
    from_hashicorp
    source=hashicorp
  fi
  sudo chmod 666 /var/run/libvirt/libvirt-sock
  echo "Installed $(vagrant --version) (source: ${source})"
  echo "source=${source}" >> "$GITHUB_OUTPUT"
}

# The PPA's packages that `apt-get install vagrant vagrant-libvirt` would
# fetch, as apt's "'URL' FILE SIZE HASH" lines. Archive packages are left
# out: the install step gets those from the archive either way.
resolve() {
  local key
  retry sudo apt-get update || true
  add_ppa
  apt-get install --print-uris -qq vagrant vagrant-libvirt | grep -F "'${PPA_URL}" > "$PPA_LIST" || true
  if [ ! -s "$PPA_LIST" ]; then
    echo '::error::ppa:evgeni/vagrant provides none of the packages for vagrant and vagrant-libvirt'
    return 1
  fi
  cat "$PPA_LIST"
  key="${PREFIX}$(awk '{ print $2 }' "$PPA_LIST" | sort | sha256sum | cut -c1-16)"
  echo "key=${key}" >> "$GITHUB_OUTPUT"
}

# apt-get download checks each file against the PPA's signed index
download() {
  local packages
  mapfile -t packages < <(awk '{ split($2, file, "_"); print file[1] }' "$PPA_LIST")
  mkdir -p "$DEBS"
  (cd "$DEBS" && retry apt-get download "${packages[@]}")
  ls -l "$DEBS"
}

case "${1:-}" in
  series | install | resolve | download) "$1" ;;
  *)
    echo "Usage: $0 series|install|resolve|download" >&2
    exit 2
    ;;
esac
