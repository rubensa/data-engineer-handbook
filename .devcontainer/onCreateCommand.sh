#!/bin/bash -i

onCreateCommand() {
  # Get current script path
  local SCRIPTPATH=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

  local DEVCONTAINER_FOLDER=${SCRIPTPATH:-$PWD/.devcontainer}
  local WORKSPACE_FOLDER=${CONTAINER_WORKSPACE_FOLDER:-$PWD}

  # Import common lib
  . ${DEVCONTAINER_FOLDER}/lib/common.sh
  # Import vscode lib
  . ${DEVCONTAINER_FOLDER}/lib/vscode.sh

  logStart "Creating"

  logEnd
}

onCreateCommand