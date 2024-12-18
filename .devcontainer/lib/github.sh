#!/bin/bash

# https://stackoverflow.com/a/58510109/3535783
[ -n "${GITHUB_LIB_IMPORTED}" ] && return; GITHUB_LIB_IMPORTED=0; # pragma once

_githubLibInit() {
  # Get current script path
  local SCRIPTPATH=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

  # Import common lib
  . ${SCRIPTPATH}/common.sh
}

_githubLibInit

# https://docs.github.com/en/rest/releases/releases?apiVersion=2022-11-28
ghGetReleases() {
  local owner=
  local repo=
  if [ $# -lt 2 ]; then
    logError "Owner or repository not specified."
    logEnd
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
  local releases=$( jq -r '.[].tag_name | select( . != null )' <<< "${releases_json}" )
  echo "$releases"
}

ghGetLatestRelease() {
  local owner=
  local repo=
  if [ $# -lt 2 ]; then
    logError "Owner or repository not specified."
    logEnd
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
  local release=$( jq -r '.tag_name | select( . != null )' <<< "${release_json}" )
  echo "$release"
}

ghReleaseExists() {
  local owner=
  local repo=
  local release=
  if [ $# -lt 3 ]; then
    logError "Owner, repository or release not specified."
    logEnd
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
    logError "Owner, repository, release or file path not specified."
    logEnd
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

ghGetContributors() {
  local owner=
  local repo=
  if [ $# -lt 2 ]; then
    logError "Owner or repository not specified."
    logEnd
    return 1
  else
    owner=$1
    repo=$2
  fi

  local contributors_url="https://api.github.com/repos/${owner}/${repo}/contributors" 
  local contributors_json=
  if [ -z "${GITHUB_TOKEN}" ]; then
    contributors_json=$(curl -sSL \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${contributors_url}")
  else
    contributors_json=$(curl -sSL \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${contributors_url}")
  fi
  local contributors=$( jq -r '.[].login | select( . != null )' <<< "${contributors_json}" )
  echo "$contributors"
}

ghUserKeys() {
  local user=
  if [ $# -lt 1 ]; then
    logError "User not specified."
    logEnd
    return 1
  else
    user=$1
  fi

  local content_url="https://github.com/${user}.keys"
  local content=$(curl -sSL \
      "${content_url}")
  echo "$content"
}

ghUserEmail() {
  local user=
  if [ $# -lt 1 ]; then
    logError "User not specified."
    logEnd
    return 1
  else
    user=$1
  fi

  local content_url="https://api.github.com/users/${user}"
  local content=
  if [ -z "${GITHUB_TOKEN}" ]; then
    content=$(curl -sSL \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${content_url}")
  else
    content=$(curl -sSL \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${content_url}")
  fi
  local email=$( jq -r '.email | select( . != null )' <<< "${content}" )
  echo "$email"
}

ghUserFromEmail() {
  local email=
  if [ $# -lt 1 ]; then
    logError "Email not specified."
    logEnd
    return 1
  else
    email=$1
  fi

  local users_url="https://api.github.com/search/users?q=${email}"
  local users_json=
  if [ -z "${GITHUB_TOKEN}" ]; then
    users_json=$(curl -sSL \
      -H "Accept: application/vnd.github.raw+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${users_url}")
  else
    users_json=$(curl -sSL \
      -H "Accept: application/vnd.github.raw+json" \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${users_url}")
  fi
  local user=$( jq -r '.items[0].login | select( . != null )' <<< "${users_json}" )
  echo "$user"
}

ghGenerateAllowedSigners() {
  local owner=
  local repo=
  if [ $# -lt 2 ]; then
    logError "Owner or repository not specified."
    logEnd
    return 1
  else
    owner=$1
    repo=$2
  fi

  local contributors=$(ghGetContributors ${owner} ${repo})
  for contributor in $contributors; do
    local email="$(ghUserEmail ${contributor})"
    if [ -z "${email}" ]; then
      continue
    fi
    local keys="$(ghUserKeys ${contributor})"
    if [ -z "${keys}" ]; then
      continue
    fi
    local xIFS=$IFS
    IFS=$'\n'       # make newlines the only separator
    for key in ${keys}; do
      printf "${email} namespaces=\"git\" ${key}\n"
    done
    IFS=$xIFS       # restore default
  done
}

# Check if the we received an existing function name as argument and execute it
[[ $(type -t $1) == function ]] && $@
