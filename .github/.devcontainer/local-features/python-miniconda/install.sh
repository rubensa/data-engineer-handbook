#!/bin/bash

# Get feature options
MINI_CONDA_VERSION=${MINICONDA_VERSION:-"latest"}
DISABLE_CONDA_ANON_USAGE=${DISABLE_CONDA_ANON_USAGE:-"true"}
CONDA_CHANNELS=${CONDA_CHANNELS:-}
ADD_CONDA_BASH_COMPLETION=${ADD_CONDA_BASH_COMPLETION:-"true"}
CONDA_BASH_COMPLETION_VERSION=${CONDA_BASH_COMPLETION_VERSION:-"latest"}
CONDA_ENVIRONMENT=${CONDA_ENVIRONMENT:-"dev"}
PYTHON_VERSION=${PYTHON_VERSION:-}
CONDA_PACKAGES=${CONDA_PACKAGES:-}
PIP_PACKAGES=${PIP_PACKAGES:-}

USERNAME="${USERNAME:-"${_REMOTE_USER:-"automatic"}"}"
UPDATE_RC="${UPDATE_RC:-"true"}"
CONDA_DIR="${CONDA_DIR:-"/usr/local/share/conda"}"

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
miniconda_install_snippet="$(cat << EOF
set -e
umask 0002
# Do not update profile - we'll do this manually
export PROFILE=/dev/null
# Check if the version exists (https://repo.anaconda.com/miniconda/)
# Only Miniconda3 versions are supported
MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-${MINICONDA_VERSION}-Linux-${architecture}.sh"
HTTP_CODE=\$(curl -o /dev/null --silent -Iw '%{http_code}' -sSL \${MINICONDA_URL})
if [ "\${HTTP_CODE}" != "200" ]; then
  echo "(!) Miniconda3 version '${MINICONDA_VERSION}' not found"
  exit 1
fi

# See https://github.com/ContinuumIO/anaconda-issues/issues/11148
mkdir ~/.conda
curl -o /tmp/miniconda.sh -sSL \${MINICONDA_URL}
# See https://docs.conda.io/projects/conda/en/latest/user-guide/install/linux.html#installing-in-silent-mode
/bin/bash -i /tmp/miniconda.sh -b -p ${CONDA_DIR}
rm /tmp/miniconda.sh
EOF
)"

# Snippet that should be added into rc / profiles
conda_rc_snippet="$(cat << EOF
export CONDA_DIR="${CONDA_DIR}"
[ -s "\$CONDA_DIR/etc/profile.d/conda.sh" ] && . "\$CONDA_DIR/etc/profile.d/conda.sh"
EOF
)"

# Create conda group to the user's UID or GID to change while still allowing access to conda
if ! cat /etc/group | grep -e "^conda:" > /dev/null 2>&1; then
  groupadd -r conda
fi
usermod -a -G conda "${USERNAME}"

# Install conda using miniconda
# Always use umask 0002 so both the owner so that everything is u+rw,g+rw
umask 0002
if [ ! -d "${CONDA_DIR}" ]; then
  bash -c "${miniconda_install_snippet}"

  # update conda dir, and set sticky bit
  chown -R "${USERNAME}:conda" "${CONDA_DIR}"
  chmod -R g+rws "${CONDA_DIR}"

  # Update rc files
  if [ "${UPDATE_RC}" = "true" ]; then
    updaterc "${conda_rc_snippet}"
  fi
else
  echo "conda already installed."
fi

# Use shared folder for packages and environments
sudo_if "printf \"envs_dirs:\\n  - ${CONDA_DIR}/envs\\npkgs_dirs:\\n   - ${CONDA_DIR}/pkgs\\n\" >> ~/.condarc"
# See https://github.com/ContinuumIO/anaconda-issues/issues/11148
sudo_if "mkdir ~/.conda"

if [ "${DISABLE_CONDA_ANON_USAGE}" = "true" ]; then
  echo "Disabling conda anonymous usage statistics..."
  sudo_if ". ${CONDA_DIR}/etc/profile.d/conda.sh && conda config --set anaconda_anon_usage off"
fi

# Add conda channels
if [ -n "${CONDA_CHANNELS}" ]; then
  echo "Adding conda channels..."
  sudo_if ". ${CONDA_DIR}/etc/profile.d/conda.sh && conda config --add channels ${CONDA_CHANNELS}"
fi

# Create conda environment
if [ -n "${PYTHON_VERSION}" ]; then
  if [ "${CONDA_ENVIRONMENT}" = "base"  ]; then
    echo "(!) Cannot install custom python version in 'base' conda environment"
    exit 1
  fi
  sudo_if "${CONDA_DIR}/bin/conda create -n ${CONDA_ENVIRONMENT} python=${PYTHON_VERSION} -y"
else
  if [ "${CONDA_ENVIRONMENT}" != "base"  ]; then
    sudo_if "${CONDA_DIR}/bin/conda create -n ${CONDA_ENVIRONMENT} -y"
  fi
fi

# Activate conda environment
# Update rc files
if [ "${UPDATE_RC}" = "true" ]; then
  updaterc "conda activate ${CONDA_ENVIRONMENT}"
fi

# Install conda bash completion
if [ "${ADD_CONDA_BASH_COMPLETION}" = "true" ]; then
  if [ ! -f "/usr/share/bash-completion/completions/conda" ]; then
    if [ "${CONDA_BASH_COMPLETION_VERSION}" = "latest" ]; then
      CONDA_BASH_COMPLETION_VERSION="$(curl https://api.github.com/repos/tartansandal/conda-bash-completion/releases/latest -s | jq .tag_name -r)"
    fi

    echo "Installing conda bash completion..."
    # Check if the version exists (https://github.com/tartansandal/conda-bash-completion/tags)
    CONDA_BASH_COMPLETION_URL="https://github.com/tartansandal/conda-bash-completion/archive/refs/tags/${CONDA_BASH_COMPLETION_VERSION}.tar.gz"
    HTTP_CODE=$(curl -o /dev/null --silent -Iw '%{http_code}' -sSL ${CONDA_BASH_COMPLETION_URL})
    if [ "${HTTP_CODE}" != "200" ]; then
      echo "(!) Conda bash completion version '${CONDA_BASH_COMPLETION_VERSION}' not found"
      exit 1
    fi

    # Install dependencies
    check_packages bash-completion

    # Install conda bash completion
    curl -o /tmp/conda-bash-completion.tar.gz -sSL ${CONDA_BASH_COMPLETION_URL}
    tar xvfz /tmp/conda-bash-completion.tar.gz --directory /tmp
    rm /tmp/conda-bash-completion.tar.gz
    cp /tmp/conda-bash-completion-${CONDA_BASH_COMPLETION_VERSION}/conda /usr/share/bash-completion/completions/conda
    chmod 644 /usr/share/bash-completion/completions/conda
    rm -rf /tmp/conda-bash-completion-${CONDA_BASH_COMPLETION_VERSION}
    chmod 644 /usr/share/bash-completion/completions/conda
  else
    echo "conda bash completion already installed."
  fi
fi

if [ -n "${CONDA_PACKAGES}" ]; then
  sudo_if ". ${CONDA_DIR}/etc/profile.d/conda.sh && conda install -n ${CONDA_ENVIRONMENT} ${CONDA_PACKAGES} -y"
fi

if [ -n "${PIP_PACKAGES}" ]; then
  sudo_if ". ${CONDA_DIR}/etc/profile.d/conda.sh && conda activate ${CONDA_ENVIRONMENT} && pip install ${PIP_PACKAGES}"
fi

# Clean up
clean_up

echo "Done!"