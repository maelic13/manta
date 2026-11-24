#!/usr/bin/env bash
set -euo pipefail

version=0.17.1

case "${RUNNER_OS:?}-${RUNNER_ARCH:?}" in
  Linux-X64)
    artifact=x86_64-linux
    expected_hash=3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a
    ;;
  Linux-ARM64)
    artifact=aarch64-linux
    expected_hash=a1546d5646eb184437918d6635ca6b762a0e889eac09cef720ee7a1ed3fe7795
    ;;
  macOS-X64)
    artifact=x86_64-macos
    expected_hash=9af07b20319fbd0c92ee46ad23e81d6a782b1aaea2cfb8dcbff35f1d2c7ddbb7
    ;;
  macOS-ARM64)
    artifact=aarch64-macos
    expected_hash=75f1bc7a1e9852f17ec9a0c1895f767c4ec56d46bc8a834920eece1d0359dd8d
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
