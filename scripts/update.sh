# shellcheck shell=bash
sources_file=${CODEXBAR_SOURCES_FILE:-nix/sources.json}
curl_command=${CODEXBAR_CURL:-curl}
nix_command=${CODEXBAR_NIX:-nix}

fail() {
  printf '%s\n' "$*" >&2
  exit 2
}

if [[ ! -f "$sources_file" ]]; then
  fail "Quelldatei nicht gefunden: $sources_file"
fi

if ! jq -e '
  type == "object"
  and (."codexbar-cli" | type == "object")
  and (."codexbar-plasma" | type == "object")
  and ([."codexbar-cli", ."codexbar-plasma"] | all(
    (.owner | type == "string" and length > 0)
    and (.repo | type == "string" and length > 0)
    and (.version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))
    and (.hash | type == "string" and test("^sha256-[A-Za-z0-9+/]{43}=$"))
  ))
  and (."codexbar-cli".asset | type == "string" and length > 0)
' "$sources_file" >/dev/null; then
  fail "Ungültiges Format in $sources_file"
fi

mode=update
if (( $# > 1 )); then
  fail "Aufruf: update [--check]"
elif (( $# == 1 )); then
  if [[ $1 != --check ]]; then
    fail "Unbekanntes Argument: $1"
  fi
  mode=check
fi

target_tmp=
cleanup() {
  if [[ -n $target_tmp ]]; then
    rm -f -- "$target_tmp"
  fi
}
trap cleanup EXIT

github_headers=(
  -H "Accept: application/vnd.github+json"
  -H "X-GitHub-Api-Version: 2022-11-28"
)
if [[ -n ${GITHUB_TOKEN:-} ]]; then
  github_headers+=( -H "Authorization: Bearer $GITHUB_TOKEN" )
fi

source_field() {
  local package=$1
  local field=$2
  jq -er --arg package "$package" --arg field "$field" '.[$package][$field]' "$sources_file"
}

version_compare() {
  local left=$1
  local right=$2
  local -a left_parts right_parts
  local index left_number right_number

  IFS=. read -r -a left_parts <<<"$left"
  IFS=. read -r -a right_parts <<<"$right"
  for index in 0 1 2; do
    left_number=$((10#${left_parts[index]}))
    right_number=$((10#${right_parts[index]}))
    if (( left_number < right_number )); then
      printf '%s\n' -1
      return
    fi
    if (( left_number > right_number )); then
      printf '%s\n' 1
      return
    fi
  done
  printf '%s\n' 0
}

fetch_release() {
  local package=$1
  local owner repo api_url raw_response status message
  owner=$(source_field "$package" owner)
  repo=$(source_field "$package" repo)
  api_url="https://api.github.com/repos/$owner/$repo/releases/latest"

  if ! raw_response=$("$curl_command" \
    --fail-with-body \
    --silent \
    --show-error \
    --location \
    --connect-timeout 15 \
    --max-time 60 \
    "${github_headers[@]}" \
    --write-out $'\n%{http_code}' \
    "$api_url"); then
    status=${raw_response##*$'\n'}
    release_response=${raw_response%$'\n'*}
    message=$(jq -r '.message // empty' <<<"$release_response" 2>/dev/null || :)
    if [[ -n $message ]]; then
      fail "GitHub-Anfrage für $owner/$repo fehlgeschlagen (HTTP $status): $message"
    fi
    fail "GitHub-Anfrage für $owner/$repo fehlgeschlagen (HTTP $status); Netzwerk oder Rate-Limit prüfen"
  fi

  status=${raw_response##*$'\n'}
  release_response=${raw_response%$'\n'*}
  if [[ $status != 200 ]]; then
    fail "GitHub-Anfrage für $owner/$repo lieferte HTTP $status"
  fi
  if ! jq -e '
    type == "object"
    and .draft == false
    and .prerelease == false
    and (.tag_name | type == "string" and test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
  ' <<<"$release_response" >/dev/null; then
    fail "Unerwartete Release-Antwort für $owner/$repo"
  fi
}

release_response=
fetch_release codexbar-cli
cli_release=$release_response
fetch_release codexbar-plasma
plasma_release=$release_response

cli_tag=$(jq -er '.tag_name' <<<"$cli_release")
plasma_tag=$(jq -er '.tag_name' <<<"$plasma_release")
cli_remote=${cli_tag#v}
plasma_remote=${plasma_tag#v}
cli_local=$(source_field codexbar-cli version)
plasma_local=$(source_field codexbar-plasma version)
cli_owner=$(source_field codexbar-cli owner)
cli_repo=$(source_field codexbar-cli repo)
plasma_owner=$(source_field codexbar-plasma owner)
plasma_repo=$(source_field codexbar-plasma repo)
cli_asset="CodexBarCLI-v${cli_remote}-linux-x86_64.tar.gz"

if [[ $(version_compare "$cli_remote" "$cli_local") == -1 ]]; then
  fail "Remote-Version für $cli_owner/$cli_repo ($cli_remote) ist älter als die lokale Pin ($cli_local)"
fi
if [[ $(version_compare "$plasma_remote" "$plasma_local") == -1 ]]; then
  fail "Remote-Version für $plasma_owner/$plasma_repo ($plasma_remote) ist älter als die lokale Pin ($plasma_local)"
fi

if ! jq -e --arg asset "$cli_asset" '
  [.assets[]? | select(
    .name == $asset
    and (.browser_download_url | type == "string" and length > 0)
  )] | length == 1
' <<<"$cli_release" >/dev/null; then
  fail "Erwartetes CLI-Asset fehlt oder ist nicht eindeutig: $cli_asset"
fi

cli_outdated=false
plasma_outdated=false
if [[ $(version_compare "$cli_remote" "$cli_local") == 1 ]]; then
  cli_outdated=true
fi
if [[ $(version_compare "$plasma_remote" "$plasma_local") == 1 ]]; then
  plasma_outdated=true
fi

if [[ $mode == check ]]; then
  jq -n \
    --arg cli_local "$cli_local" \
    --arg cli_remote "$cli_remote" \
    --argjson cli_outdated "$cli_outdated" \
    --arg plasma_local "$plasma_local" \
    --arg plasma_remote "$plasma_remote" \
    --argjson plasma_outdated "$plasma_outdated" \
    '{
      "codexbar-cli": {
        local: $cli_local,
        remote: $cli_remote,
        outdated: $cli_outdated
      },
      "codexbar-plasma": {
        local: $plasma_local,
        remote: $plasma_remote,
        outdated: $plasma_outdated
      }
    }'
  if [[ $cli_outdated == true || $plasma_outdated == true ]]; then
    exit 10
  fi
  exit 0
fi

if [[ $cli_outdated == false && $plasma_outdated == false ]]; then
  exit 0
fi

cli_url="https://github.com/$cli_owner/$cli_repo/releases/download/$cli_tag/$cli_asset"
plasma_url="https://github.com/$plasma_owner/$plasma_repo/archive/refs/tags/$plasma_tag.tar.gz"

if ! cli_prefetch=$("$nix_command" store prefetch-file --json "$cli_url"); then
  fail "Hash-Ermittlung für $cli_asset fehlgeschlagen"
fi
if ! cli_hash=$(jq -er '.hash | select(type == "string" and test("^sha256-[A-Za-z0-9+/]{43}=$"))' <<<"$cli_prefetch"); then
  fail "Nix lieferte keinen gültigen Hash für $cli_asset"
fi

if ! plasma_prefetch=$("$nix_command" store prefetch-file --json --unpack "$plasma_url"); then
  fail "Hash-Ermittlung für $plasma_owner/$plasma_repo fehlgeschlagen"
fi
if ! plasma_hash=$(jq -er '.hash | select(type == "string" and test("^sha256-[A-Za-z0-9+/]{43}=$"))' <<<"$plasma_prefetch"); then
  fail "Nix lieferte keinen gültigen Hash für $plasma_owner/$plasma_repo"
fi

target_tmp=$(mktemp "${sources_file}.tmp.XXXXXX")
if ! jq \
  --arg cli_version "$cli_remote" \
  --arg cli_asset "$cli_asset" \
  --arg cli_hash "$cli_hash" \
  --arg plasma_version "$plasma_remote" \
  --arg plasma_hash "$plasma_hash" \
  '."codexbar-cli".version = $cli_version
   | ."codexbar-cli".asset = $cli_asset
   | ."codexbar-cli".hash = $cli_hash
   | ."codexbar-plasma".version = $plasma_version
   | ."codexbar-plasma".hash = $plasma_hash' \
  "$sources_file" >"$target_tmp"; then
  fail "Aktualisierte Quelldatei konnte nicht erzeugt werden"
fi
chmod --reference="$sources_file" "$target_tmp"
mv -- "$target_tmp" "$sources_file"
target_tmp=
