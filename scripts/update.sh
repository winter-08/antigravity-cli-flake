base_url="https://storage.googleapis.com/antigravity-public/antigravity-cli"

version=$(curl --fail --silent --show-error --location "$base_url/latest" | tr -d '[:space:]')
if [[ -z $version ]]; then
  echo "Failed to determine latest Antigravity CLI version" >&2
  exit 1
fi

if [[ -f sources.json ]] && [[ $(jq --raw-output .version sources.json) == "$version" ]]; then
  echo "Already at Antigravity CLI $version"
  exit 0
fi

manifest=$(curl --fail --silent --show-error --location "$base_url/$version/manifest.json")

whole_version=$(jq --exit-status --raw-output '.platforms."linux-x64".url | split("/")[5]' <<<"$manifest")
build_id=${whole_version#"$version"-}

to_sri() {
  local key=$1
  local hex
  hex=$(jq --exit-status --raw-output --arg key "$key" '.platforms[$key].sha512' <<<"$manifest")
  nix --extra-experimental-features nix-command hash convert --hash-algo sha512 --to sri "$hex"
}

url_for() {
  local key=$1
  jq --exit-status --raw-output --arg key "$key" '.platforms[$key].url' <<<"$manifest"
}

# Verify that the corresponding GitHub release tag is also published so the
# fallback mirror in fetchurl is valid.
auth=()
if [[ -n ${GITHUB_TOKEN:-} ]]; then
  auth=(--header "Authorization: Bearer $GITHUB_TOKEN")
fi
curl --fail --silent --show-error --location "${auth[@]}" \
  "https://api.github.com/repos/google-antigravity/antigravity-cli/releases/tags/$version" >/dev/null

jq --null-input \
  --arg version "$version" \
  --arg buildId "$build_id" \
  --arg linux_x64_url "$(url_for linux-x64)" \
  --arg linux_x64_hash "$(to_sri linux-x64)" \
  --arg linux_x64_musl_url "$(url_for linux-x64-musl)" \
  --arg linux_x64_musl_hash "$(to_sri linux-x64-musl)" \
  --arg linux_arm_url "$(url_for linux-arm)" \
  --arg linux_arm_hash "$(to_sri linux-arm)" \
  --arg linux_arm_musl_url "$(url_for linux-arm-musl)" \
  --arg linux_arm_musl_hash "$(to_sri linux-arm-musl)" \
  --arg darwin_x64_url "$(url_for darwin-x64)" \
  --arg darwin_x64_hash "$(to_sri darwin-x64)" \
  --arg darwin_arm_url "$(url_for darwin-arm)" \
  --arg darwin_arm_hash "$(to_sri darwin-arm)" \
  '{
    version: $version,
    buildId: $buildId,
    platforms: {
      "x86_64-linux": {
        glibc: {
          gcsUrl: $linux_x64_url,
          githubAsset: "agy_cli_linux_x64.tar.gz",
          hash: $linux_x64_hash
        },
        musl: {
          gcsUrl: $linux_x64_musl_url,
          githubAsset: "agy_cli_linux_x64_musl.tar.gz",
          hash: $linux_x64_musl_hash
        }
      },
      "aarch64-linux": {
        glibc: {
          gcsUrl: $linux_arm_url,
          githubAsset: "agy_cli_linux_arm64.tar.gz",
          hash: $linux_arm_hash
        },
        musl: {
          gcsUrl: $linux_arm_musl_url,
          githubAsset: "agy_cli_linux_arm64_musl.tar.gz",
          hash: $linux_arm_musl_hash
        }
      },
      "x86_64-darwin": {
        darwin: {
          gcsUrl: $darwin_x64_url,
          githubAsset: "agy_cli_mac_x64.tar.gz",
          hash: $darwin_x64_hash
        }
      },
      "aarch64-darwin": {
        darwin: {
          gcsUrl: $darwin_arm_url,
          githubAsset: "agy_cli_mac_arm64.tar.gz",
          hash: $darwin_arm_hash
        }
      }
    }
  }' >sources.json

echo "Pinned Antigravity CLI $version ($build_id)"
