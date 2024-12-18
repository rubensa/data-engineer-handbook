#!/bin/bash -i

# Snippet that should be added into .devcontainer/.env.local
env_local_snippet="$(cat << EOF
EOF
)"

initializeCommand() {
  # Get current script path
  local SCRIPTPATH=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

  # Import vscode lib
  . ${SCRIPTPATH}/lib/vscode.sh
  # Import docker lib
  . ${SCRIPTPATH}/lib/docker.sh

  logStart "Initializing"

  # Make sure required env vars are set
  envVarsSetted GITHUB_TOKEN || exit 1

  # This checks if CODESPACES env var is set
  envVarSetted CODESPACES
  # If it is set the return value is 0
  if [[ $? -ne 0 ]]; then
    # We need to login to GitHub Container Registry (ghcr.io) to be able to pull devcontainer images
    log "Login to GitHub Container Registry (ghcr.io)"
    echo $GITHUB_TOKEN | docker login ghcr.io -u ${GITHUB_USER:-USERNAME} --password-stdin
  fi

  # Make sure Docker network is created
  dockerNetworkCreate "dtngnrhndbk" || exit 1

  # Make sure Docker volume to store VSCode Server extensions cache is created
  dockerVolumeCreate "vscode-server-extensions-cache" || exit 1
  # Make sure Docker volume to store Conda packages cache is created
  dockerVolumeCreate "conda-packages-cache" || exit 1
  # Make sure Docker volume to store pip cache is created
  dockerVolumeCreate "pip-cache" || exit 1

  # HOME is not defined in CODESPACES
  # Define it here based on devcontainer --user-data-folder parameter
  HOME=${HOME:-/var/lib/docker/codespacemount/.persistedshare}

  # Create user .ssh folder if it does not already exists
  if [ ! -e ${HOME}/.ssh ]; then
    log "Creating ${HOME}/.ssh folder"
    mkdir -p ${HOME}/.ssh
  fi

  # Create user git config file if it does not already exists
  if [ ! -e ${HOME}/.gitconfig ]; then
    log "Creating ${HOME}/.gitconfig file"
    touch ${HOME}/.gitconfig
  fi

  # Create PyPI config file if it does not already exists
  if [ ! -f ${HOME}/.pypirc ]; then
    log "Creating ${HOME}/.pypirc file"
    touch ${HOME}/.pypirc
    chmod 600 ${HOME}/.pypirc
  fi

  # Create ${SCRIPTPATH}/.env file if it does not already exists
  if [ ! -e ${SCRIPTPATH}/.env ]; then
    log "Creating ${SCRIPTPATH}/.env file"
    touch ${SCRIPTPATH}/.env
  fi

  # Load environment variables from ${SCRIPTPATH}/.env
  loadDotEnv ${SCRIPTPATH}/.env
  if [ $? -ne 0 ]; then
    logError "Error loading ${SCRIPTPATH}/.env file"
    logEnd
    return 1
  fi

  # Set HOME environment variable if not already set
  # HOME is not defined in CODESPACES (add to .env so it is available for docker-compose.yml)
  if ! envVarSetted HOME; then
    log "Setting HOME into ${SCRIPTPATH}/.env file"
    appendToFile ${SCRIPTPATH}/.env "HOME=${HOME}"
  fi

  # Create .devcontainer/.env.local file if it does not already exists
  if [ ! -e .devcontainer/.env.local ]; then
    log "Creating file '.devcontainer/.env.local'..."
    echo "${env_local_snippet}" > ${DEVCONTAINER_FOLDER}/.env.local
    echo "File '.devcontainer/.env.local' created."
  fi

  logEnd
}

initializeCommand