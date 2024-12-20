#!/bin/bash

# https://stackoverflow.com/a/58510109/3535783
[ -n "${DOCKER_LIB_IMPORTED}" ] && return; DOCKER_LIB_IMPORTED=0; # pragma once

_dockerLibInit() {
  # Get current script path
  local SCRIPTPATH=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

  # Import common lib
  . ${SCRIPTPATH}/common.sh
}

_dockerLibInit

dockerNetworkCreate() {
  logStart "Creating Docker network $1"

  local network_name=
  if [ $# -eq 0 ]; then
    logError "Network name not specified."
    logEnd
    return 1
  else
    network_name=$1
  fi

  docker network inspect ${network_name} >/dev/null 2>&1

  if [ $? -eq 0 ]; then
    log "Network ${network_name} already exists"
  else
    docker network create ${network_name}
    if [ $? -ne 0 ]; then
      logError "Error creating network ${network_name}"
      logEnd
      return 1
    fi
    log "Network ${network_name} created"
  fi
  logEnd
}

dockerVolumeCreate() {
  logStart "Creating Docker volume $1"

  local volume_name=
  if [ $# -eq 0 ]; then
    logError "Volume name not specified."
    logEnd
    return 1
  else
    volume_name=$1
  fi

  docker volume inspect ${volume_name} >/dev/null 2>&1

  if [ $? -eq 0 ]; then
    log "Volume ${volume_name} already exists"
  else
    docker volume create ${volume_name}
    [ $? -eq 0 ]  || logEndReturnError "Error creating volume ${volume_name}"
    log "Volume ${volume_name} created"
  fi
  logEnd
}

# Check if the we received an existing function name as argument and execute it
[[ $(type -t $1) == function ]] && $@
