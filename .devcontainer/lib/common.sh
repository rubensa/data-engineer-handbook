#!/bin/bash

# https://stackoverflow.com/a/58510109/3535783
[ -n "${COMMON_LIB_IMPORTED}" ] && return; COMMON_LIB_IMPORTED=0; # pragma once

##################
## LOG MESSAGES ##
##################

LOG_INDENT="*"
LOG_STACK=()

log() {
  printf "%s%s\n" "[${LOG_INDENT}]" " $*"
}

logWarn() {
  log "[Warn] $*"
}

logError() {
  echo "[Error] $*" >>/dev/stderr
}

logStart() {
  log "$* - start"
  LOG_INDENT="${LOG_INDENT}*"
  LOG_STACK+=("$*")
}

logEnd() {
  LOG_INDENT="${LOG_INDENT%?}"
  log "${LOG_STACK[${#LOG_STACK[@]}-1]} - end"
  unset LOG_STACK[${#LOG_STACK[@]}-1]
}

###################################
## ENVIRONMENT VARIABLES SUPPORT ##
###################################

# https://stackoverflow.com/a/60652702/3535783
envVarSetted() {
  local env_var=
  if [ $# -eq 0 ]; then
    logWarn "Environment variable not specified."
    return 1
  else
    env_var=$(declare -p "$1" 2>/dev/null)
  fi
  if [[ !  $env_var =~ ^declare\ -x ]]; then
    logWarn "$1 environment variable not set."
    return 1
  fi
}

envVarsSetted() {
  local env_var=
  for env_var in "$@"; do
    envVarSetted "$env_var" || return 1
  done
}

unsetEnvVars() {
  logStart "Unsetting $@ environment variables"
  local env_var=
  for env_var in "$@"; do
    unset $env_var
  done
  logEnd
}

##################
## FILE SUPPORT ##
##################

fileExists() {
  local file=
  if [ $# -eq 0 ]; then
    logError "File not specified."
    return 1
  else
    file=$1
  fi
  if [ ! -f "$file" ]; then
    logError "$file file does not exists."
    return 1
  fi
}

fileEmpty() {
  local file=
  if [ $# -eq 0 ]; then
    logError "File not specified."
    return 1
  else
    file=$1
  fi
  if [ ! -f "$file" ]; then
    logError "$file file does not exists."
    return 1
  fi
  if [ -s "$file" ]; then
    logError "$file file is not empty."
    return 1
  fi
}

appendToFile() {
  logStart "Appending ${@:2} to $1"
  local file=
  if [ $# -eq 0 ]; then
    logError "File not specified."
    logEnd
    return 1
  else
    file=$1
  fi

  fileExists $file
  if [ $? -eq 1 ]; then
    logEnd
    return 1
  fi

  fileEmpty $file
  if [ $? -eq 1 ]; then
    # check if file ends with newline
    if [[ $(tail -c1 "$1" | wc -l) -eq 0 ]]; then
      # add new newline
      echo "" >> $file
    fi
  fi

  shift
  for env_var in "$@"; do
    echo "$env_var" >> $file
  done
  logEnd
}

####################
## FOLDER SUPPORT ##
####################

# Sync folder content (any file or folder)
folderSync () {
  logStart "Syncing $1 and $2 content"
  if [ "$#" -lt 2 ]; then
    logError "Folders not specified."
    logEnd
    return 1
  fi
  if [ -d $1 ] || [ -d $2 ]; then
    [ -d $1 ] || mkdir -p $1
    [ -d $2 ] || mkdir -p $2

    # copy both ways (aka sync)
    cp -r -n $1/* $2/ 2>/dev/null
    cp -r -n $2/* $1/ 2>/dev/null
  fi
  logEnd
}

# Sync subfolders only
subFoldersSync () {
  logStart "Syncing $1 and $2 subfolders"
  if [ "$#" -lt 2 ]; then
    logError "Folders not specified."
    logEnd
    return 1
  fi
  if [ -d $1 ] || [ -d $2 ]; then
    [ -d $1 ] || mkdir -p $1
    [ -d $2 ] || mkdir -p $2

    # for each subfolder (not symbolic links) in any of the two folders
    for sub_folder in $(find $1 $2 -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort | uniq); do
      folderSync $1/$sub_folder $2/$sub_folder
    done
  fi
  logEnd
}

#####################
## DOT ENV SUPPORT ##
#####################

loadDotEnv() {
  logStart "Loading environment variables from $1"
  local dot_env_file=
  if [ $# -eq 0 ]; then
    logError "Dot env file not specified."
    logEnd
    return 1
  else
    dot_env_file=$1
  fi

  fileExists $dot_env_file
  if [ $? -eq 1 ]; then
    logEnd
    return 1
  fi

  set -a # set -o allexport
  . $dot_env_file
  set +a # set +o allexport
  logEnd
}

# Check if the we received an existing function name as argument and execute it
[[ $(type -t $1) == function ]] && $@
