#!/bin/bash

# Get feature options
NVM_VERSION=${NVM_VERSION:-"latest"}
ADD_NVM_BASH_COMPLETION=${ADD_NVM_BASH_COMPLETION:-"true"}
NODE_VERSION=${NODE_VERSION:-"lts"}
ADD_NODE_BASH_COMPLETION=${ADD_NODE_BASH_COMPLETION:-"true"}
ADD_NPM_BASH_COMPLETION=${ADD_NPM_BASH_COMPLETION:-"true"}
NPM_PACKAGES=${NPM_PACKAGES:-}

USERNAME="${USERNAME:-"${_REMOTE_USER:-"automatic"}"}"
UPDATE_RC="${UPDATE_RC:-"true"}"
NVM_DIR="${NVM_DIR:-"/usr/local/share/nvm"}"

FEATURE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Exit if any errors occur
set -eux

# Import feature-utils
. ${FEATURE_DIR}/scripts/feature-utils.sh

# Check if the script is run as root
check_root

# Ensure architecture is supported (and set ARCHITECTURE global variable)
check_architecture "x86_64" "aarch64"

# Check if the Linux distro is supported (and set the DISTRO global variable to 'debian' or 'rhel')
check_distro

# Clean up the package manager cache
clean_up

# Ensure that login shells get the correct path if the user updated the PATH using ENV.
setup_restore_env

# Determine the appropriate non-root user (and set the USERNAME global variable)
set_username

# Ensure apt is in non-interactive to avoid prompts
export DEBIAN_FRONTEND=noninteractive

# Install dependencies
check_packages curl ca-certificates gnupg2

# Install snipppet that we will run as root
nvm_install_snippet="$(cat << EOF
# Import github-utils
. ${FEATURE_DIR}/scripts/github-utils.sh

set -e
umask 0002
# Do not update profile - we'll do this manually
export PROFILE=/dev/null
# Check if the version exists (https://github.com/nvm-sh/nvm/releases)
if [ "\${NVM_VERSION}" = "latest" ]; then
  NVM_VERSION="\$(ghGetLatestRelease nvm-sh nvm)"
else
  ghReleaseExists nvm-sh nvm \${NVM_VERSION}
  if [ \$? -ne 0 ]; then
    echo "(!) NVM version '\${NVM_VERSION}' not found"
    exit 1
  fi
fi

ghGetReleaseFile nvm-sh nvm \${NVM_VERSION} install.sh > /tmp/nvm.sh
mkdir -p ${NVM_DIR}
export NVM_DIR=${NVM_DIR}
/bin/bash -i /tmp/nvm.sh --no-use
rm /tmp/nvm.sh
# Create nvm cache directory so it is owned by the group
mkdir -p ${NVM_DIR}/.cache
# Assign group folder ownership
chgrp -R nvm ${NVM_DIR}
# Set the segid bit to the folder and give write and exec acces so any member of group can use it
chmod -R g+rws ${NVM_DIR}
EOF
)"

# Snippet that should be added into rc / profiles
nvm_rc_snippet="$(cat << EOF
export NVM_DIR="${NVM_DIR}"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
EOF
)"

# Install node snippet
node_install_snippet="$(cat << EOF
set -e
umask 0002
export NVM_DIR=${NVM_DIR}
. ${NVM_DIR}/nvm.sh
nvm install ${NODE_VERSION}
EOF
)"

  # ln -s \$(dirname \$(dirname \$(nvm which $NODE_VERSION))) ${NVM_DIR}/versions/node/current
  # sudo ln -s ${NVM_DIR}/versions/node/current/bin/node /usr/bin/node

# Create nvm group to the user's UID or GID to change while still allowing access to nvm
if ! cat /etc/group | grep -e "^nvm:" > /dev/null 2>&1; then
  groupadd -r nvm
fi
usermod -a -G nvm "${USERNAME}"

# Install nvm
# Always use umask 0002 so both the owner so that everything is u+rw,g+rw
umask 0002
if [ ! -d "${NVM_DIR}" ]; then
  bash -c "${nvm_install_snippet}"

  # update nvm dir, and set sticky bit
  chown -R "${USERNAME}:nvm" "${NVM_DIR}"
  chmod -R g+rws "${NVM_DIR}"

  # Update rc files
  if [ "${UPDATE_RC}" = "true" ]; then
    updaterc "${nvm_rc_snippet}"
  fi
else
  echo "nvm already installed."
fi

# Install node version
if [ -n "${NODE_VERSION}" ]; then
  sudo_if "${node_install_snippet}"
fi

# Setup bash completion
if [ "${ADD_NVM_BASH_COMPLETION}" = "true" ] || [ "${ADD_NODE_BASH_COMPLETION}" = "true" ] || [ "${ADD_NPM_BASH_COMPLETION}" = "true" ]; then
  # Install dependencies
  check_packages bash-completion

  if [ "${ADD_NVM_BASH_COMPLETION}" = "true" ]; then
    # nvm bash completion
    ln -s $NVM_DIR/bash_completion /usr/share/bash-completion/completions/nvm
  fi

  # We can setup bash completion for node and npm only if node is installed
  if [ -n "${NODE_VERSION}" ]; then
    if [ "${ADD_NODE_BASH_COMPLETION}" = "true" ]; then
      # node bash completion
      bash -c ". ${NVM_DIR}/nvm.sh; node --completion-bash > /usr/share/bash-completion/completions/node"
      chmod 644 /usr/share/bash-completion/completions/node
    fi

    if [ "${ADD_NPM_BASH_COMPLETION}" = "true" ]; then
      # npm bash completion
      bash -c ". ${NVM_DIR}/nvm.sh; echo \"\$(npm completion)\" > /usr/share/bash-completion/completions/npm"
      chmod 644 /usr/share/bash-completion/completions/npm
    fi
  fi
fi

if [ -n "${NPM_PACKAGES}" ]; then
  sudo_if ". ${NVM_DIR}/nvm.sh; npm install -g ${NPM_PACKAGES}"
fi

# Clean up
clean_up

echo "Done!"