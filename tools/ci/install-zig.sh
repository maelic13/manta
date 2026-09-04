#!/usr/bin/env bash
set -euo pipefail

version=0.16.0

case "${RUNNER_OS:?}-${RUNNER_ARCH:?}" in
  Linux-X64)
    artifact=x86_64-linux
    expected_hash=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00
    ;;
  Linux-ARM64)
    artifact=aarch64-linux
    expected_hash=ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17
    ;;
  macOS-X64)
    artifact=x86_64-macos
    expected_hash=0387557ed1877bc6a2e1802c8391953baddba76081876301c522f52977b52ba7
    ;;
  macOS-ARM64)
    artifact=aarch64-macos
    expected_hash=b23d70deaa879b5c2d486ed3316f7eaa53e84acf6fc9cc747de152450d401489
    ;;
  *)
    printf 'Unsupported runner: %s-%s\n' "$RUNNER_OS" "$RUNNER_ARCH" >&2
    exit 1
    ;;
esac

install_directory="${RUNNER_TEMP:?}/zig-$version"
zig_executable="$install_directory/zig"

if [[ ! -x "$zig_executable" ]]; then
  archive="$RUNNER_TEMP/$artifact-$version.tar.xz"
  staging="$RUNNER_TEMP/manta-zig-extract-$version"
  if [[ -e "$install_directory" ]]; then
    printf 'Cached Zig directory is incomplete: %s\n' "$install_directory" >&2
    exit 1
  fi
  rm -rf -- "$staging"

  url="https://ziglang.org/download/$version/zig-$artifact-$version.tar.xz"
  printf 'Downloading %s\n' "$url"
  curl --fail --location --retry 3 --retry-all-errors \
    --connect-timeout 20 --max-time 300 --output "$archive" "$url"

  if [[ "$RUNNER_OS" == Linux ]]; then
    printf '%s  %s\n' "$expected_hash" "$archive" | sha256sum --check --strict
  else
    actual_hash=$(shasum -a 256 "$archive" | cut -d ' ' -f 1)
    [[ "$actual_hash" == "$expected_hash" ]] || {
      printf 'Zig archive checksum mismatch: expected %s, received %s.\n' \
        "$expected_hash" "$actual_hash" >&2
      exit 1
    }
  fi

  mkdir -p -- "$staging"
  tar -xf "$archive" -C "$staging"
  mv -- "$staging/zig-$artifact-$version" "$install_directory"
  rm -rf -- "$staging"
  rm -f -- "$archive"
fi

actual_version=$($zig_executable version)
if [[ "$actual_version" != "$version" ]]; then
  printf "Expected Zig %s, received '%s'.\n" "$version" "$actual_version" >&2
  exit 1
fi
printf '%s\n' "$install_directory" >> "${GITHUB_PATH:?}"
printf 'Using Zig %s from %s\n' "$actual_version" "$install_directory"
