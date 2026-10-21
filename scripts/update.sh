#!/usr/bin/env bash

set -euo pipefail
shopt -s inherit_errexit

usage() {
  echo "Usage: $0 octelium|octelium-desktop [TAG]" >&2
  exit 2
}

root_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sources_directory="${SOURCES_DIRECTORY:-$root_directory/sources}"

octelium_binaries=("octelium" "octeliumctl" "octops")
octelium_systems=("x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin")
desktop_systems=("x86_64-linux" "aarch64-linux")
temporary_directory=""

log() { echo "$*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

get_repository() {
  case "$1" in
    octelium) echo "octelium/octelium" ;;
    octelium-desktop) echo "octelium/octelium-desktop" ;;
    *) return 1 ;;
  esac
}

get_os() {
  case "$1" in
    *-linux) echo "linux" ;;
    *-darwin) echo "darwin" ;;
    *) return 1 ;;
  esac
}

get_arch() {
  case "$1" in
    x86_64-*) echo "amd64" ;;
    aarch64-*) echo "arm64" ;;
    *) return 1 ;;
  esac
}

get_deb_arch() {
  case "$1" in
    x86_64-linux) echo "amd64" ;;
    aarch64-linux) echo "arm64" ;;
    *) return 1 ;;
  esac
}

is_valid_tag() {
  [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

is_newer_version() {
  [[ "$1" != "$2" && "$(printf '%s\n' "$1" "$2" | sort -V | tail -n 1)" == "$1" ]]
}

hex_to_sri() {
  [[ "$1" =~ ^[0-9a-f]{64}$ ]] || return 1

  local escaped="" i
  for ((i = 0; i < 64; i += 2)); do
    escaped+="\\x${1:i:2}"
  done

  printf 'sha256-%s\n' "$(printf '%b' "$escaped" | base64 | tr -d '\n')"
}

get_checksum() {
  local checksums_file="$1" file_name="$2" ret

  ret="$(awk -v name="$file_name" '{
    entry = substr($0, length($1) + 2)
    sub(/^[ *]/, "", entry)
    gsub(/ /, ".", entry)
    if (entry == name) print $1
  }' "$checksums_file")"
  [[ -n "$ret" && "$(wc -l <<< "$ret")" -eq 1 ]] || return 1
  echo "$ret"
}

find_asset() {
  local assets_file="$1" pattern="$2" ret

  ret="$(jq -r --arg pattern "$pattern" '.[] | select(.name | test($pattern)) | .name' "$assets_file")"
  [[ -n "$ret" && "$(wc -l <<< "$ret")" -eq 1 ]] || return 1
  echo "$ret"
}

get_asset_field() {
  jq -er --arg name "$2" --arg field "$3" '.[] | select(.name == $name) | .[$field] // ""' "$1"
}

get_desktop_deb_pattern() {
  local system="$1" version="$2"

  echo "^octelium-desktop-linux-$(get_arch "$system")-.+_${version//./\\.}_$(get_deb_arch "$system")\\.deb$"
}

get_latest_tag() {
  gh release view --repo "$1" --json tagName --jq .tagName
}

list_assets() {
  gh release view "$2" --repo "$1" --json assets --jq '[.assets[] | { name, url, digest }]' > "$3"
}

verify_asset() {
  local repository="$1" tag="$2" directory="$3" file_name="$4" expected actual digest

  expected="$(get_checksum "$directory/SHA256SUMS" "$file_name")" ||
    die "Could not find a single checksum of $file_name in SHA256SUMS"
  read -r actual _ <<< "$(sha256sum "$directory/$file_name")"
  [[ "$actual" == "$expected" ]] ||
    die "Checksum mismatch for $file_name: expected $expected in SHA256SUMS, got $actual"

  digest="$(get_asset_field "$directory/assets.json" "$file_name" digest)" ||
    die "Could not find the release asset $file_name"
  [[ -z "$digest" || "$digest" == "sha256:$actual" ]] ||
    die "Checksum mismatch for $file_name: expected $digest from GitHub, got $actual"

  gh attestation verify "$directory/$file_name" \
    --repo "$repository" \
    --bundle "$directory/release-attestation.json" \
    --signer-workflow "$repository/.github/workflows/release.yaml" \
    --source-ref "refs/tags/$tag" \
    --deny-self-hosted-runners > /dev/null ||
    die "Could not verify the provenance attestation of $file_name"

  hex_to_sri "$actual"
}

download_assets() {
  local repository="$1" tag="$2" directory="$3"
  shift 3

  local args=() name
  for name in "$@"; do
    args+=(--pattern "$name")
  done

  gh release download "$tag" --repo "$repository" --dir "$directory" --clobber "${args[@]}"

  for name in "$@"; do
    [[ -s "$directory/$name" ]] || die "Could not download $name of $repository $tag"
  done
}

add_asset() {
  local assets="$1" path="$2" repository="$3" tag="$4" directory="$5" file_name="$6" url hash

  url="$(get_asset_field "$directory/assets.json" "$file_name" url)"
  [[ "$url" == "https://github.com/$repository/releases/download/$tag/"* ]] ||
    die "Unexpected download URL of $file_name: $url"
  hash="$(verify_asset "$repository" "$tag" "$directory" "$file_name")"

  jq -c --argjson path "$path" --arg url "$url" --arg hash "$hash" \
    'setpath($path; { url: $url, hash: $hash })' <<< "$assets"
}

update_octelium() {
  local repository="$1" tag="$2" directory="$3" output="$4"
  local version="${tag#v}" assets="{}" files=() system binary file_name

  for system in "${octelium_systems[@]}"; do
    for binary in "${octelium_binaries[@]}"; do
      files+=("$binary-$(get_os "$system")-$(get_arch "$system").tar.gz")
    done
  done

  download_assets "$repository" "$tag" "$directory" SHA256SUMS release-attestation.json "${files[@]}"

  for system in "${octelium_systems[@]}"; do
    for binary in "${octelium_binaries[@]}"; do
      file_name="$binary-$(get_os "$system")-$(get_arch "$system").tar.gz"
      assets="$(add_asset "$assets" "[\"$system\", \"$binary\"]" \
        "$repository" "$tag" "$directory" "$file_name")"
    done
  done

  jq -n --arg version "$version" --argjson assets "$assets" \
    '{ version: $version, assets: $assets }' > "$output"
}

update_octelium_desktop() {
  local repository="$1" tag="$2" directory="$3" output="$4"
  local version="${tag#v}" assets="{}" files=() system file_name octelium_tag

  for system in "${desktop_systems[@]}"; do
    file_name="$(find_asset "$directory/assets.json" "$(get_desktop_deb_pattern "$system" "$version")")" ||
      die "Could not find a single Debian package for $system in the release assets"
    files+=("$file_name")
  done

  download_assets "$repository" "$tag" "$directory" \
    SHA256SUMS release-attestation.json OCTELIUM_CLI_VERSION-linux-amd64 "${files[@]}"

  verify_asset "$repository" "$tag" "$directory" OCTELIUM_CLI_VERSION-linux-amd64 > /dev/null
  octelium_tag="$(tr -d '[:space:]' < "$directory/OCTELIUM_CLI_VERSION-linux-amd64")"
  is_valid_tag "$octelium_tag" || die "Invalid Octelium CLI version: $octelium_tag"

  for system in "${desktop_systems[@]}"; do
    file_name="$(find_asset "$directory/assets.json" "$(get_desktop_deb_pattern "$system" "$version")")"
    assets="$(add_asset "$assets" "[\"$system\"]" "$repository" "$tag" "$directory" "$file_name")"
  done

  jq -n \
    --arg version "$version" \
    --arg octeliumVersion "${octelium_tag#v}" \
    --argjson assets "$assets" \
    '{ version: $version, minimumOcteliumVersion: $octeliumVersion, assets: $assets }' > "$output"
}

main() {
  [[ $# -ge 1 && $# -le 2 ]] || usage

  local project="$1" requested_tag="${2:-}" repository source_file current_version tag
  repository="$(get_repository "$project")" || usage
  source_file="$sources_directory/$project.json"

  for command_name in gh jq sha256sum base64 awk sort; do
    command -v "$command_name" > /dev/null 2>&1 || die "Required command is not installed: $command_name"
  done

  current_version=""
  if [[ -f "$source_file" ]]; then
    current_version="$(jq -r .version "$source_file")"
  fi

  if [[ -n "$requested_tag" ]]; then
    tag="$requested_tag"
  else
    tag="$(get_latest_tag "$repository")" || die "Could not resolve the latest release of $repository"
  fi
  is_valid_tag "$tag" || die "Invalid release tag: $tag"

  if [[ "${tag#v}" == "$current_version" ]]; then
    log "$project is already at $current_version"
    return 0
  fi

  if [[ -z "$requested_tag" && -n "$current_version" ]] && ! is_newer_version "${tag#v}" "$current_version"; then
    log "The latest release $tag of $project is older than the current version $current_version, skipping"
    return 0
  fi

  temporary_directory="$(mktemp -d)"
  trap 'rm -rf "$temporary_directory"' EXIT

  log "Updating $project from ${current_version:-none} to ${tag#v}"

  list_assets "$repository" "$tag" "$temporary_directory/assets.json"

  case "$project" in
    octelium) update_octelium "$repository" "$tag" "$temporary_directory" "$temporary_directory/source.json" ;;
    octelium-desktop) update_octelium_desktop "$repository" "$tag" "$temporary_directory" "$temporary_directory/source.json" ;;
  esac

  mkdir -p "$sources_directory"
  cp "$temporary_directory/source.json" "$source_file.tmp"
  mv "$source_file.tmp" "$source_file"

  log "Updated $source_file"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
