#!/usr/bin/env bash

set -euo pipefail
shopt -s inherit_errexit

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_directory="$(mktemp -d)"
trap 'rm -rf "$work_directory"' EXIT

export FAKE_RELEASES="$work_directory/releases"
export SOURCES_DIRECTORY="$work_directory/sources"
mkdir -p "$work_directory/bin" "$FAKE_RELEASES" "$SOURCES_DIRECTORY"

{
  echo "#!$BASH"
  cat <<'EOF'

set -euo pipefail

printf '%s\n' "$*" >> "$FAKE_RELEASES/calls.log"

command="$1 $2"
shift 2

tag=""
file=""
repository=""
directory=""
json=""
signer_workflow=""
source_ref=""
bundle=""
patterns=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repository="$2"; shift 2 ;;
    --dir) directory="$2"; shift 2 ;;
    --pattern) patterns+=("$2"); shift 2 ;;
    --json) json="$2"; shift 2 ;;
    --jq) shift 2 ;;
    --signer-workflow) signer_workflow="$2"; shift 2 ;;
    --source-ref) source_ref="$2"; shift 2 ;;
    --bundle) bundle="$2"; shift 2 ;;
    --clobber | --deny-self-hosted-runners) shift ;;
    -*) echo "Unexpected flag: $1" >&2; exit 1 ;;
    *)
      if [[ "$command" == "attestation verify" ]]; then
        file="$1"
      else
        tag="$1"
      fi
      shift
      ;;
  esac
done

release="$FAKE_RELEASES/$repository/$tag"

case "$command" in
  "release view")
    if [[ "$json" == "tagName" ]]; then
      cat "$FAKE_RELEASES/$repository/latest"
      exit 0
    fi
    [[ -d "$release" ]] || { echo "release not found" >&2; exit 1; }
    for asset in "$release"/assets/*; do
      name="$(basename "$asset")"
      read -r digest _ <<< "$(sha256sum "$asset")"
      jq -n \
        --arg name "$name" \
        --arg url "https://github.com/$repository/releases/download/$tag/$name" \
        --arg digest "sha256:$digest" \
        '{ name: $name, url: $url, digest: $digest }'
    done | jq -s .
    ;;
  "release download")
    [[ -d "$release" ]] || { echo "release not found" >&2; exit 1; }
    for pattern in "${patterns[@]}"; do
      cp "$release/assets/$pattern" "$directory/"
    done
    ;;
  "attestation verify")
    tag="${source_ref#refs/tags/}"
    [[ "$signer_workflow" == "$repository/.github/workflows/release.yaml" ]]
    [[ -f "$bundle" ]]
    if grep -qxF "$(basename "$file")" "$FAKE_RELEASES/$repository/$tag/unattested" 2> /dev/null; then
      exit 1
    fi
    ;;
  *)
    echo "Unexpected command: $command" >&2
    exit 1
    ;;
esac
EOF
} > "$work_directory/bin/gh"
chmod +x "$work_directory/bin/gh"
export PATH="$work_directory/bin:$PATH"

make_octelium_release() {
  local tag="$1" release="$FAKE_RELEASES/octelium/octelium/$1"

  mkdir -p "$release/assets"
  for binary in octelium octeliumctl octops; do
    for platform in linux-amd64 linux-arm64 darwin-amd64 darwin-arm64; do
      printf '%s %s %s\n' "$binary" "$platform" "$tag" > "$release/assets/$binary-$platform.tar.gz"
      printf '%s %s %s\n' "$binary" "$platform" "$tag" > "$release/assets/${binary}_${tag#v}-1_${platform#*-}.deb"
    done
  done
  (cd "$release/assets" && sha256sum -- *.tar.gz *.deb > SHA256SUMS)
  echo '{}' > "$release/assets/release-attestation.json"
  echo "$tag" > "$FAKE_RELEASES/octelium/octelium/latest"
}

make_desktop_release() {
  local tag="$1" octelium_tag="$2" release="$FAKE_RELEASES/octelium/octelium-desktop/$1"
  local version="${1#v}"

  mkdir -p "$release/assets"
  for platform in amd64:amd64:x86_64 arm64:arm64:aarch64; do
    IFS=: read -r arch deb_arch rpm_arch <<< "$platform"
    printf 'deb %s\n' "$arch" > "$release/assets/octelium-desktop-linux-$arch-Octelium.Desktop_${version}_${deb_arch}.deb"
    printf 'rpm %s\n' "$arch" > "$release/assets/octelium-desktop-linux-$arch-Octelium.Desktop-${version}-1.${rpm_arch}.rpm"
    printf 'appimage %s\n' "$arch" > "$release/assets/octelium-desktop-linux-$arch-Octelium.Desktop_${version}_${deb_arch}.AppImage"
    printf '%s\n' "$octelium_tag" > "$release/assets/OCTELIUM_CLI_VERSION-linux-$arch"
  done
  (cd "$release/assets" && sha256sum -- octelium-desktop-* OCTELIUM_CLI_VERSION-* | sed 's/Octelium\.Desktop/Octelium Desktop/' > SHA256SUMS)
  echo '{}' > "$release/assets/release-attestation.json"
  echo "$tag" > "$FAKE_RELEASES/octelium/octelium-desktop/latest"
}

sri() {
  printf 'sha256-%s\n' "$(openssl dgst -sha256 -binary "$1" | base64 | tr -d '\n')"
}

update() {
  "$repository_root/scripts/update.sh" "$@"
}

fails() {
  if "$@"; then
    echo "Expected a failure: $*" >&2
    exit 1
  fi
}

(
  source "$repository_root/scripts/update.sh"

  [[ "$(hex_to_sri 3f04ff25f3c2d58bbcd9319d082d0d43c7998bd910591d21ef2c39d27e40dd53)" == \
    "sha256-PwT/JfPC1Yu82TGdCC0NQ8eZi9kQWR0h7yw50n5A3VM=" ]]
  [[ "$(hex_to_sri 00000000000000000000000000000000000000000000000000000000000000ff)" == \
    "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP8=" ]]
  fails hex_to_sri 3F04 > /dev/null

  is_valid_tag v1.2.3
  fails is_valid_tag 1.2.3
  fails is_valid_tag v1.2
  fails is_valid_tag v1.2.3-rc.1

  is_newer_version 0.10.0 0.9.0
  fails is_newer_version 0.9.0 0.10.0
  fails is_newer_version 0.9.0 0.9.0

  printf '%s  %s\n%s *%s\n' \
    1111 "octelium-desktop-linux-amd64-Octelium Desktop_0.2.8_amd64.deb" \
    2222 "octops-linux-arm64.tar.gz" > "$work_directory/SHA256SUMS"
  [[ "$(get_checksum "$work_directory/SHA256SUMS" "octelium-desktop-linux-amd64-Octelium.Desktop_0.2.8_amd64.deb")" == "1111" ]]
  [[ "$(get_checksum "$work_directory/SHA256SUMS" "octops-linux-arm64.tar.gz")" == "2222" ]]
  fails get_checksum "$work_directory/SHA256SUMS" "octops-linux-amd64.tar.gz" > /dev/null

  [[ "$(get_desktop_deb_pattern aarch64-linux 0.2.8)" == '^octelium-desktop-linux-arm64-.+_0\.2\.8_arm64\.deb$' ]]
)

make_octelium_release v0.46.0
update octelium
source_file="$SOURCES_DIRECTORY/octelium.json"
jq -e '.version == "0.46.0"' "$source_file" > /dev/null
jq -e '.assets | keys == ["aarch64-darwin", "aarch64-linux", "x86_64-darwin", "x86_64-linux"]' "$source_file" > /dev/null
jq -e 'all(.assets[]; keys == ["octelium", "octeliumctl", "octops"])' "$source_file" > /dev/null
jq -e '.assets["aarch64-darwin"].octops.url == "https://github.com/octelium/octelium/releases/download/v0.46.0/octops-darwin-arm64.tar.gz"' "$source_file" > /dev/null
jq -e --arg hash "$(sri "$FAKE_RELEASES/octelium/octelium/v0.46.0/assets/octops-darwin-arm64.tar.gz")" \
  '.assets["aarch64-darwin"].octops.hash == $hash' "$source_file" > /dev/null
[[ "$(grep -c '^attestation verify' "$FAKE_RELEASES/calls.log")" == "12" ]]
grep -qF -- "--source-ref refs/tags/v0.46.0" "$FAKE_RELEASES/calls.log"

: > "$FAKE_RELEASES/calls.log"
update octelium
fails grep -q '^release download' "$FAKE_RELEASES/calls.log"

make_octelium_release v0.45.0
cp "$source_file" "$work_directory/expected.json"
update octelium
cmp "$source_file" "$work_directory/expected.json"

update octelium v0.45.0
jq -e '.version == "0.45.0"' "$source_file" > /dev/null

make_octelium_release v0.47.0
echo "corrupted" >> "$FAKE_RELEASES/octelium/octelium/v0.47.0/assets/octeliumctl-linux-arm64.tar.gz"
cp "$source_file" "$work_directory/expected.json"
fails update octelium 2> "$work_directory/error.log"
grep -qF "Checksum mismatch for octeliumctl-linux-arm64.tar.gz" "$work_directory/error.log"
cmp "$source_file" "$work_directory/expected.json"

make_octelium_release v0.47.0
echo "octelium-darwin-amd64.tar.gz" > "$FAKE_RELEASES/octelium/octelium/v0.47.0/unattested"
fails update octelium 2> "$work_directory/error.log"
grep -qF "Could not verify the provenance attestation of octelium-darwin-amd64.tar.gz" "$work_directory/error.log"
cmp "$source_file" "$work_directory/expected.json"

rm "$FAKE_RELEASES/octelium/octelium/v0.47.0/unattested"
update octelium
jq -e '.version == "0.47.0"' "$source_file" > /dev/null

fails update octelium 0.47.0 2> /dev/null
fails update octelium-cli 2> /dev/null

make_desktop_release v0.2.8 v0.46.0
update octelium-desktop
source_file="$SOURCES_DIRECTORY/octelium-desktop.json"
jq -e '.version == "0.2.8" and .minimumOcteliumVersion == "0.46.0"' "$source_file" > /dev/null
jq -e '.assets | keys == ["aarch64-linux", "x86_64-linux"]' "$source_file" > /dev/null
jq -e '.assets["x86_64-linux"].url == "https://github.com/octelium/octelium-desktop/releases/download/v0.2.8/octelium-desktop-linux-amd64-Octelium.Desktop_0.2.8_amd64.deb"' "$source_file" > /dev/null
jq -e --arg hash "$(sri "$FAKE_RELEASES/octelium/octelium-desktop/v0.2.8/assets/octelium-desktop-linux-arm64-Octelium.Desktop_0.2.8_arm64.deb")" \
  '.assets["aarch64-linux"].hash == $hash' "$source_file" > /dev/null

make_desktop_release v0.2.9 v0.46.0
cp "$FAKE_RELEASES/octelium/octelium-desktop/v0.2.9/assets/octelium-desktop-linux-amd64-Octelium.Desktop_0.2.9_amd64.deb" \
  "$FAKE_RELEASES/octelium/octelium-desktop/v0.2.9/assets/octelium-desktop-linux-amd64-Other_0.2.9_amd64.deb"
cp "$source_file" "$work_directory/expected.json"
fails update octelium-desktop 2> "$work_directory/error.log"
grep -qF "Could not find a single Debian package for x86_64-linux" "$work_directory/error.log"
cmp "$source_file" "$work_directory/expected.json"

echo "Update script tests passed."
