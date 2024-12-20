# https://docs.github.com/en/rest/releases/releases?apiVersion=2022-11-28
ghGetReleases() {
  local owner=
  local repo=
  if [ $# -lt 2 ]; then
    echo -e 'Owner or repository not specified.'
    return 1
  else
    owner=$1
    repo=$2
  fi

  local releases_url="https://api.github.com/repos/${owner}/${repo}/releases"
  local releases_json=
  if [ -z "${GITHUB_TOKEN}" ]; then
    releases_json=$(curl -sSL \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${releases_url}")
  else
    releases_json=$(curl -sSL \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${releases_url}")
  fi
  local releases=$( jq -r '.[].tag_name' <<< "${releases_json}" )
  echo "$releases"
}

ghGetLatestRelease() {
  local owner=
  local repo=
  if [ $# -lt 2 ]; then
    echo -e 'Owner or repository not specified.'
    return 1
  else
    owner=$1
    repo=$2
  fi

  local release_url="https://api.github.com/repos/${owner}/${repo}/releases/latest"
  local release_json=
  if [ -z "${GITHUB_TOKEN}" ]; then
    release_json=$(curl -sSL \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${release_url}")
  else
    release_json=$(curl -sSL \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${release_url}")
  fi
  local release=$( jq -r '.tag_name' <<< "${release_json}" )
  echo "$release"
}

ghReleaseExists() {
  local owner=
  local repo=
  local release=
  if [ $# -lt 3 ]; then
    echo -e 'Owner, repository or release not specified.'
    return 1
  else
    owner=$1
    repo=$2
    release=$3
  fi

  local releases=$(ghGetReleases ${owner} ${repo})
  for r in $releases; do
    if [ "$r" == "$release" ]; then
      return 0
    fi
  done
  return 1
}

ghGetReleaseFile() {
  local owner=
  local repo=
  local release=
  local path=
  if [ $# -lt 4 ]; then
    echo -e 'Owner, repository, release or file path not specified.'
    return 1
  else
    owner=$1
    repo=$2
    release=$3
    path=$4
  fi

  local content_url="https://api.github.com/repos/${owner}/${repo}/contents/${path}?ref=${release}"
  local content=
  if [ -z "${GITHUB_TOKEN}" ]; then
    content=$(curl -sSL \
      -H "Accept: application/vnd.github.raw+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${content_url}")
  else
    content=$(curl -sSL \
      -H "Accept: application/vnd.github.raw+json" \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${content_url}")
  fi
  echo "$content"

}
