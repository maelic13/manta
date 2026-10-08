#!/usr/bin/env bash
set -euo pipefail

version=0.17.0

case "${RUNNER_OS:?}-${RUNNER_ARCH:?}" in
  Linux-X64)
    artifact=x86_64-linux
    expected_hash=1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026
    ;;
  Linux-ARM64)
    artifact=aarch64-linux
    expected_hash=9e8d11661d4ae3bd57702a3832781e23ad151dde5798e16a5ccd503f65234ff8
    ;;
  macOS-X64)
    artifact=x86_64-macos
    expected_hash=4f9a1c5269aa17ebda5e6d3c2b89d6cbf36f7d2b22a0306e9ab98f25f95529c6
    ;;
  macOS-ARM64)
    artifact=aarch64-macos
    expected_hash=b607e9b9234790a008116ae5bdb71c6243b84b9fb42a53a9e70fde41c06c536a
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
