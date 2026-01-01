#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2024 hyperpolymath
# asdf-ada utility functions

set -euo pipefail

# GNAT-FSF-builds repository for releases
readonly GNAT_FSF_REPO="alire-project/GNAT-FSF-builds"
readonly GITHUB_API_URL="https://api.github.com"
readonly GITHUB_RELEASES_URL="https://github.com/${GNAT_FSF_REPO}/releases/download"

# Tool name for this plugin (exported for use by asdf)
export TOOL_NAME="ada"
export TOOL_CMD="gnat"

# Colors for output (disabled if not a tty)
if [[ -t 2 ]]; then
  readonly RED='\033[0;31m'
  readonly GREEN='\033[0;32m'
  readonly YELLOW='\033[0;33m'
  readonly BLUE='\033[0;34m'
  readonly NC='\033[0m' # No Color
else
  readonly RED=''
  readonly GREEN=''
  readonly YELLOW=''
  readonly BLUE=''
  readonly NC=''
fi

# Logging functions
log_info() {
  echo -e "${BLUE}[asdf-ada]${NC} $*" >&2
}

log_success() {
  echo -e "${GREEN}[asdf-ada]${NC} $*" >&2
}

log_warn() {
  echo -e "${YELLOW}[asdf-ada]${NC} WARNING: $*" >&2
}

log_error() {
  echo -e "${RED}[asdf-ada]${NC} ERROR: $*" >&2
}

fail() {
  log_error "$*"
  exit 1
}

# Detect the current platform
get_platform() {
  local os
  os="$(uname -s)"
  case "${os}" in
    Linux*)  echo "linux" ;;
    Darwin*) echo "darwin" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows64" ;;
    *) fail "Unsupported operating system: ${os}" ;;
  esac
}

# Detect the current architecture
get_arch() {
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64|amd64) echo "x86_64" ;;
    aarch64|arm64) echo "aarch64" ;;
    *) fail "Unsupported architecture: ${arch}" ;;
  esac
}

# Get the download URL for a specific version
get_download_url() {
  local version="${1}"
  local platform arch filename tag_name

  platform="$(get_platform)"
  arch="$(get_arch)"

  # Determine tag name format based on version pattern
  if [[ "${version}" == *"-snapshot"* ]]; then
    # Snapshot version: gnat-16.0.0-snapshot
    tag_name="gnat-${version}"
    # Snapshot filenames include date, need to query API
    filename="$(get_snapshot_filename "${version}" "${arch}" "${platform}")"
  else
    # Stable version: gnat-15.2.0-1
    tag_name="gnat-${version}"
    filename="gnat-${arch}-${platform}-${version}.tar.gz"
  fi

  echo "${GITHUB_RELEASES_URL}/${tag_name}/${filename}"
}

# Get the checksum URL for a specific version
get_checksum_url() {
  local version="${1}"
  local download_url
  download_url="$(get_download_url "${version}")"
  echo "${download_url}.sha256"
}

# Query API for snapshot filename (includes date)
get_snapshot_filename() {
  local version="${1}"
  local arch="${2}"
  local platform="${3}"
  local tag_name="gnat-${version}"

  local api_url="${GITHUB_API_URL}/repos/${GNAT_FSF_REPO}/releases/tags/${tag_name}"
  local response

  response="$(curl_wrapper "${api_url}")" || fail "Failed to query API for snapshot version"

  # Extract filename matching our arch/platform
  echo "${response}" | grep -oE "gnat-${arch}-${platform}-[0-9.]+-[0-9]+\.tar\.gz" | head -1
}

# Wrapper for curl with proper headers
curl_wrapper() {
  local url="${1}"
  shift
  local extra_args=("$@")

  local -a curl_args=(
    --silent
    --show-error
    --fail
    --location
    --retry 3
    --retry-delay 2
  )

  # Add GitHub token if available for rate limiting
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl_args+=(--header "Authorization: token ${GITHUB_TOKEN}")
  elif [[ -n "${GITHUB_API_TOKEN:-}" ]]; then
    curl_args+=(--header "Authorization: token ${GITHUB_API_TOKEN}")
  fi

  # Use safe array expansion for potentially empty extra_args
  curl "${curl_args[@]}" ${extra_args[@]+"${extra_args[@]}"} "${url}"
}

# Download a file with progress indication
download_file() {
  local url="${1}"
  local output="${2}"

  local -a curl_args=(
    --fail
    --location
    --retry 3
    --retry-delay 2
    --output "${output}"
  )

  # Show progress if interactive
  if [[ -t 1 ]]; then
    curl_args+=(--progress-bar)
  else
    curl_args+=(--silent --show-error)
  fi

  # Add GitHub token if available
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl_args+=(--header "Authorization: token ${GITHUB_TOKEN}")
  elif [[ -n "${GITHUB_API_TOKEN:-}" ]]; then
    curl_args+=(--header "Authorization: token ${GITHUB_API_TOKEN}")
  fi

  curl "${curl_args[@]}" "${url}"
}

# Verify SHA256 checksum
verify_checksum() {
  local file="${1}"
  local checksum_file="${2}"

  local expected_checksum actual_checksum

  # Read expected checksum (file format: "hash  filename" or just "hash")
  expected_checksum="$(cut -d' ' -f1 < "${checksum_file}")"

  # Calculate actual checksum
  if command -v sha256sum &>/dev/null; then
    actual_checksum="$(sha256sum "${file}" | cut -d' ' -f1)"
  elif command -v shasum &>/dev/null; then
    actual_checksum="$(shasum -a 256 "${file}" | cut -d' ' -f1)"
  else
    log_warn "No SHA256 command found, skipping verification"
    return 0
  fi

  if [[ "${expected_checksum}" != "${actual_checksum}" ]]; then
    fail "Checksum verification failed!\n  Expected: ${expected_checksum}\n  Got: ${actual_checksum}"
  fi

  log_success "Checksum verified"
}

# List all available versions from GitHub releases
list_all_versions() {
  local api_url="${GITHUB_API_URL}/repos/${GNAT_FSF_REPO}/releases"
  local response versions

  response="$(curl_wrapper "${api_url}?per_page=100")" || fail "Failed to fetch releases from GitHub"

  # Extract version numbers from tag names (format: gnat-X.Y.Z or gnat-X.Y.Z-N)
  # Filter to only include native gnat releases, not arm-elf, avr-elf, etc.
  versions="$(echo "${response}" | grep -oE '"tag_name":\s*"gnat-[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+|-snapshot)?"' | \
              sed -E 's/"tag_name":\s*"gnat-([^"]+)"/\1/' | \
              sort -t. -k1,1n -k2,2n -k3,3n)"

  # Return one version per line (asdf standard format)
  echo "${versions}"
}

# Get the latest stable version
get_latest_stable() {
  # Filter out snapshots and get the highest version
  list_all_versions | grep -v "snapshot" | sort -t. -k1,1rn -k2,2rn -k3,3rn | head -1
}

# Check if a command exists
command_exists() {
  command -v "$1" &>/dev/null
}

# Ensure required tools are available
check_dependencies() {
  local deps=("curl" "tar" "grep" "sed" "sort" "cut" "mkdir" "rm")
  local missing=()

  for dep in "${deps[@]}"; do
    if ! command_exists "${dep}"; then
      missing+=("${dep}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    fail "Missing required dependencies: ${missing[*]}"
  fi
}
