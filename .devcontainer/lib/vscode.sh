#!/bin/bash

# https://stackoverflow.com/a/58510109/3535783
[ -n "${VSCODE_LIB_IMPORTED}" ] && return; VSCODE_LIB_IMPORTED=0; # pragma once

_vscodeLibInit() {
  # Get current script path
  local SCRIPTPATH=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

  # Import common lib
  . ${SCRIPTPATH}/common.sh
}

_vscodeLibInit

#######################
## GIT HOOKS SUPPORT ##
#######################

setUpGitHooks() {
  logStart "Setting up git hooks"
  # Get current script path
  local SCRIPTPATH=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

  for file in ${SCRIPTPATH}/../git-hooks/*; do
    filename=${file##*/}
    ln -s -f ../../.devcontainer/git-hooks/$filename ${SCRIPTPATH}/../../.git/hooks/$filename
    log "Git hook ${filename} set"
  done
  logEnd
}

#########################
## GIT FILTERS SUPPORT ##
#########################

setUpGitFilters() {
  logStart "Setting up git filters"
  # Get current script path
  local SCRIPTPATH=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

  for file in ${SCRIPTPATH}/../git-filters/*; do
    filename=${file##*/}
    if [[ "$filename" == *.required ]]; then
      git config filter.$filename $(cat $file)
    else
      git config filter.$filename .devcontainer/git-filters/$filename
    fi
    log "Git filter ${filename} set"
  done
  logEnd
}

###############################
## VSCODE EXTENSIONS SUPPORT ##
###############################

installExtensions() {
  logStart "Installing extensions specified in $@"

  local extensions_file=
  if [ $# -eq 0 ]; then
    logError "Extensions file not specified."
    logEnd
    return 1
  fi

  # Install extensions if file exists
  for extensions_file in "$@"
  do
    if  [ -e ${extensions_file} ]; then
      extensions+=( $(sed '/^[[:blank:]]*#/d;s/\/\/.*//' ${extensions_file} | jq -r -c '.extensions[]') )
    else
      logWarn "Could not find ${extensions_file} file"
    fi
  done

  if [ ! ${#extensions[@]} -eq 0 ]; then
    local code_command=
    if ls ~/.vscode-server/bin/*/bin/remote-cli/code > /dev/null 2>&1; then
      code_command=$(ls ~/.vscode-server/bin/*/bin/remote-cli/code | head -n 1)
    elif ls -f ~/.vscode-server-insiders/bin/*/bin/remote-cli/code > /dev/null 2>&1; then
      code_command=$(ls ~/.vscode-server-insiders/bin/*/bin/remote-cli/code | head -n 1)
    elif ls -f ~/.vscode-remote/bin/*/bin/remote-cli/code > /dev/null 2>&1; then
      code_command=$(ls ~/.vscode-remote/bin/*/bin/remote-cli/code | head -n 1)
    else
      logError "Could not find code command"
      logEnd
      return 1
    fi

    echo "$code_command"
    for extension in "${extensions[@]}"; do
      installed_extensions=( $($code_command --list-extensions) )
      if [[ ${installed_extensions[@]} =~ ${extension} ]]; then
        log "Extension ${extension} already installed"
        continue
      fi
      $code_command --install-extension ${extension} --force --verbose
      if [ $? -ne 0 ]; then
        logError "Could not install extension ${extension}"
        logEnd
        return 1
      fi
    done
  fi

  logEnd
}

installCustomExtension() {
  logStart "Installing custom extension $1"

  local extension_name=
  if [ $# -eq 0 ]; then
    logError "Extension name not specified."
    logEnd
    return 1
  else
    extension_name=$1
  fi

  local code_command=
  local extensionsCache_path=
  if ls ~/.vscode-server/bin/*/bin/remote-cli/code > /dev/null 2>&1; then
    code_command=$(ls ~/.vscode-server/bin/*/bin/remote-cli/code | head -n 1)
    extensionsCache_path=/vscode/vscode-server/extensionsCache
  elif ls -f ~/.vscode-server-insiders/bin/*/bin/remote-cli/code > /dev/null 2>&1; then
    code_command=$(ls ~/.vscode-server-insiders/bin/*/bin/remote-cli/code | head -n 1)
    extensionsCache_path=/vscode/vscode-server-insiders/extensionsCache
  elif ls -f ~/.vscode-remote/bin/*/bin/remote-cli/code > /dev/null 2>&1; then
    code_command=$(ls ~/.vscode-remote/bin/*/bin/remote-cli/code | head -n 1)
    extensionsCache_path=/vscode/vscode-server/extensionsCache
  else
    logError "Could not find code command"
    logEnd
    return 1
  fi

  if [ ! -f ${extensionsCache_path}/${extension_name} ]; then
    if [ -f ".devcontainer/extensions/${extension_name}.vsix" ]; then
      log "Copying ${extension_name} extension"
      sudo cp .devcontainer/extensions/${extension_name}.vsix ${extensionsCache_path}/${extension_name}
    else
      local extension_download_url=
      if [ $# -eq 1 ]; then
        logError "Extension download URL not specified."
        logEnd
        return 1
      else
        extension_download_url=$2
      fi
      log "Downloading ${extension_name} extension"
      sudo curl -sSL ${extension_download_url} -o ${extensionsCache_path}/${extension_name}
    fi
  fi
  sudo cp ${extensionsCache_path}/${extension_name} /tmp/${extension_name}.vsix
  $code_command --install-extension /tmp/${extension_name}.vsix --force --verbose

  logEnd
}

# see: https://github.com/microsoft/vsmarketplace/issues/238#issuecomment-2289479690
# see: https://github.com/microsoft/vscode/blob/main/src/vs/platform/extensionManagement/common/extensionGalleryService.ts
getExtensionData() {
  local publisher=
  local package=
  if [ $# -lt 2 ]; then
    logError "Publisher or package not specified."
    logEnd
    return 1
  else
    publisher=$1
    package=$2
  fi

  # The flag value is used to customize the output from the API.
  # A value of 16863 will return everything, or combine any number of flags using bitwise OR,
  # i.e. if you only wanted includeLatestVersionOnly (512) along with includeCategoryAndTags (4)
  # you'd use 516 for the flag.
  #
  # "none": 0,
  # "includeVersions": 1,
  # "includeFiles": 2,
  # "includeCategoryAndTags": 4,
  # "includeSharedAccounts": 8,
  # "includeVersionProperties": 16,
  # "excludeNonValidated": 32,
  # "includeInstallationTargets": 64,
  # "includeAssetUri": 128,
  # "includeStatistics": 256,
  # "includeLatestVersionOnly": 512,
  # "useFallbackAssetUri": 1024,
  # "includeMetadata": 2048,
  # "includeMinimalPayloadForVsIde": 4096,
  # "includeLcids": 8192,
  # "includeSharedOrganizations": 16384,
  # "includeNameConflictInfo": 32768,
  # "allAttributes": 16863
  json_data=$(cat <<EOT
{
  "assetTypes": [],
  "filters": [
    {
      "criteria": [
        {
          "filterType": 7,
          "value": "${publisher}.${package}"
        }
      ],
      "pageNumber": 1,
      "pageSize": 1
    }
  ],
  "flags": 16863
}
EOT
  )

  local marketplace_url="https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery"
  local response_json=$(curl -sSL \
      -H "Accept: application/json;api-version=3.0-preview.1" \
      -H "Content-Type: application/json" \
      --data "$json_data" \
      "${marketplace_url}")
  local data=$( jq 'select( . != null )' <<< "${response_json}" )
  echo "${data}"
}

getExtensionReleases() {
  local publisher=
  local package=
  if [ $# -lt 2 ]; then
    logError "Publisher or package not specified."
    logEnd
    return 1
  else
    publisher=$1
    package=$2
  fi

  # local releases=$( jq -r '.results[0].extensions[0].versions[].version | select( . != null )' <<< "$(getExtensionData ${publisher} ${package})" )
  local releases=$( jq -r '.results[0].extensions[0] | del(.versions[] | select(.properties[].key == "Microsoft.VisualStudio.Code.PreRelease")) | .versions[].version | select( . != null )' <<< "$(getExtensionData ${publisher} ${package})" )
  echo "$releases"
}

getLatestExtensionRelease() {
  local publisher=
  local package=
  if [ $# -lt 2 ]; then
    logError "Publisher or package not specified."
    logEnd
    return 1
  else
    publisher=$1
    package=$2
  fi

  # local release=$( jq -r '.results[0].extensions[0].versions[0].version | select( . != null )' <<< "$(getExtensionData ${publisher} ${package})" )
  local release=$( jq -r '.results[0].extensions[0] | del(.versions[] | select(.properties[].key == "Microsoft.VisualStudio.Code.PreRelease")) | .versions[0].version | select( . != null )' <<< "$(getExtensionData ${publisher} ${package})" )
  echo "$release"
}

##########################################
## VSCODE REPOSITORY CONTAINERS SUPPORT ##
##########################################

enableRepositoryContainersConfig() {
  logStart "Enabling repository containers config"

  local project_name=
  if [ $# -eq 0 ]; then
    logError "Project name not specified."
    logEnd
    return 1
  else
    project_name=$1
  fi

  # Get current script path
  local SCRIPTPATH=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
  local DEV_CONTAINER_FOLDER=$( cd -- "$( dirname -- "${SCRIPTPATH}" )" &> /dev/null && pwd )

  # Create .env file if it does not already exists
  if [ ! -e ${DEV_CONTAINER_FOLDER}/.env ]; then
    log "Creating ${DEV_CONTAINER_FOLDER}/.env file"
    touch ${DEV_CONTAINER_FOLDER}/.env
  fi

  # Set environment variables in .env
  loadDotEnv ${DEV_CONTAINER_FOLDER}/.env
  if [ $? -ne 0 ]; then
    logError "Error loading ${DEV_CONTAINER_FOLDER}/.env file"
    logEnd
    return 1
  fi

  # Set repositoryConfigurationPath environment variable if not already set
  if ! envVarSetted repositoryConfigurationPath; then
    log "Setting repositoryConfigurationPath into ${DEV_CONTAINER_FOLDER}/.env file"
    printf "\nrepositoryConfigurationPath=${DEV_CONTAINER_FOLDER}\n" >> ${DEV_CONTAINER_FOLDER}/.env
  fi

  # Create .env if it does not already exists
  if [ ! -e .env ]; then
    log "Creating .env file"
    touch .env
  fi
  # Set environment variables in .env
  loadDotEnv .env
  if [ $? -ne 0 ]; then
    logError "Error loading .env file"
    logEnd
    return 1
  fi
  # Set COMPOSE_PROJECT_NAME environment variable if not already set
  if ! envVarSetted COMPOSE_PROJECT_NAME; then
    log "Setting COMPOSE_PROJECT_NAME into .env file"
    printf "\nCOMPOSE_PROJECT_NAME=${project_name}\n" >> .env
  fi

  logEnd
}

###########################
## VSCODE SDKMAN SUPPORT ##
###########################

# Syncronize SDKMan candidates cache
syncSDKManCandidatesCache() {
  logStart "Syncronizing SDKMan candidates cache"
  # If both folders exist
  if [ -d /opt/sdkman/candidates ] && [ -d ~/.sdkman/candidates ]; then
    # For each language in any of the two folders
    for language in $(find /opt/sdkman/candidates ~/.sdkman/candidates -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort | uniq); do
      subFoldersSync /opt/sdkman/candidates/$language ~/.sdkman/candidates/$language
    done
  else
    logWarn "SDKMan candidates cache not syncronized"
  fi
  logEnd
}

# Syncronize LTeX library cache for valentjn.vscode-ltex VSCode extension
syncLTeXLibraryCache() {
  logStart "Syncronizing LTeX library cache"
  # Get valentjn.vscode-ltex VSCode extension folder path
  vscode_ltex_dir=$(find ~/.vscode-server/extensions/ -maxdepth 1 -name valentjn.vscode-ltex-\* -type d -print 2>/dev/null | head -n1)
  if [ -d "$vscode_ltex_dir" ] && [ -d ~/.ltex ]; then
    subFoldersSync "$vscode_ltex_dir/lib" ~/.ltex/lib
  else
    logWarn "LTeX library cache not syncronized"
  fi
  # Get valentjn.vscode-ltex VSCode extension folder path (vscode insiders)
  vscode_ltex_dir=$(find ~/.vscode-server-insiders/extensions/ -maxdepth 1 -name valentjn.vscode-ltex-\* -type d -print 2>/dev/null | head -n1)
  if [ -d "$vscode_ltex_dir" ] && [ -d ~/.ltex ]; then
    subFoldersSync "$vscode_ltex_dir/lib" ~/.ltex/lib
  else
    logWarn "LTeX library insiders cache not syncronized"
  fi
  logEnd
}

# Check if the we received an existing function name as argument and execute it
[[ $(type -t $1) == function ]] && $@
