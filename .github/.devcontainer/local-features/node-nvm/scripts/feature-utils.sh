# dynamically set $variable_name($1)=$values($2...) to globals scope
function _set2globals()
{
    if (( $# < 2 )); then
        printf "$FUNCNAME: expect at least 2 argument, but %d you given.\n" $# >&2
        exit 1
    fi
    local ___pattern_='^[_a-zA-Z][_0-9a-zA-Z]*$'
    if [[ ! $1 =~ $___pattern_ ]]; then
        printf "$FUNCNAME: invalid variable name: %s.\n" "$1" >&2
        exit 1
    fi
    local __variable__name__=$1
    shift
    local ___v_
    local ___values_=()
    while (($# > 0)); do
        ___v_=\'${1//"'"/"'\''"}\'
        ___values_=("${___values_[@]}" "$___v_") # push to array
        shift
    done

    eval $__variable__name__=\("${___values_[@]}"\)
}

# Check if the script is being run as root
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
  fi
}

# Ensure architecture is supported
check_architecture() {
  if [ $# -eq 0 ]; then
    echo -e 'Supported architectures not specified.'
    exit 1
  fi

  supported_architectures=("$@")

  architecture="$(uname -m)"
  # aarch64 and arm64 are the same
  if [ $architecture = "aarch64" ] || [ $architecture = "arm64" ]; then
      architecture=aarch64
  fi

  for supported_architecture in "${supported_architectures[@]}"; do
    if [ "${architecture}" == "${supported_architecture}" ]; then
      _set2globals ARCHITECTURE $architecture
      return
    fi
  done

  echo "(!) Architecture $architecture unsupported."
  exit 1
}

# Check if the Linux distro is supported (and set the DISTRO global variable to 'debian' or 'rhel')
check_distro() {
  # Bring in ID, ID_LIKE, VERSION_ID, VERSION_CODENAME
  . /etc/os-release
  # Get an adjusted ID independent of distro variants
  MAJOR_VERSION_ID=$(echo ${VERSION_ID} | cut -d . -f 1)
  if [ "${ID}" = "debian" ] || [ "${ID_LIKE}" = "debian" ]; then
    _set2globals DISTRO "debian"
  elif [[ "${ID}" = "rhel" || "${ID}" = "fedora" || "${ID}" = "mariner" || "${ID_LIKE}" = *"rhel"* || "${ID_LIKE}" = *"fedora"* || "${ID_LIKE}" = *"mariner"* ]]; then
    _set2globals DISTRO "rhel"
    if [[ "${ID}" = "rhel" ]] || [[ "${ID}" = *"alma"* ]] || [[ "${ID}" = *"rocky"* ]]; then
      VERSION_CODENAME="rhel${MAJOR_VERSION_ID}"
    else
      VERSION_CODENAME="${ID}${MAJOR_VERSION_ID}"
    fi
  else
    echo "Linux distro ${ID} not supported."
    exit 1
  fi
}

# Setup INSTALL_CMD & PKG_MGR_CMD
setup_install_and_pkg_mgr_cmd() {
  if type apt-get > /dev/null 2>&1; then
    _set2globals PKG_MGR_CMD apt-get
    _set2globals INSTALL_CMD "apt-get -y install --no-install-recommends"
  elif type microdnf > /dev/null 2>&1; then
    _set2globals PKG_MGR_CMD microdnf
    _set2globals INSTALL_CMD "microdnf -y install --refresh --best --nodocs --noplugins --setopt=install_weak_deps=0"
  elif type dnf > /dev/null 2>&1; then
    _set2globals PKG_MGR_CMD dnf
    _set2globals INSTALL_CMD "dnf -y install"
  else
    _set2globals PKG_MGR_CMD yum
    _set2globals INSTALL_CMD "yum -y install"
  fi
}

# Clean up the package manager cache
clean_up() {
  # Make sure we have an DISTRO ID
  [[ -z "${DISTRO:-}" ]] && check_distro

  case ${DISTRO} in
    debian)
      rm -rf /var/lib/apt/lists/*
      ;;
    rhel)
      rm -rf /var/cache/dnf/* /var/cache/yum/*
      rm -f /etc/yum.repos.d/yarn.repo
      ;;
  esac
}

# Ensure that login shells get the correct path if the user updated the PATH using ENV.
setup_restore_env() {
  rm -f /etc/profile.d/00-restore-env.sh
  echo "export PATH=${PATH//$(sh -lc 'echo $PATH')/\$PATH}" > /etc/profile.d/00-restore-env.sh
  chmod +x /etc/profile.d/00-restore-env.sh
}

# Update /etc/bash.bashrc and /etc/zsh/zshrc if the UPDATE_RC environment variable is set to true
updaterc() {
  # Make sure we have an adjusted ID
  [[ -z "${DISTRO:-}" ]] && check_distro

  local _bashrc
  local _zshrc
  if [ "${UPDATE_RC}" = "true" ]; then
    case $DISTRO in
      debian)
        _bashrc=/etc/bash.bashrc
        _zshrc=/etc/zsh/zshrc
        ;;
      rhel)
        _bashrc=/etc/bashrc
        _zshrc=/etc/zshrc
      ;;
    esac
    echo "Updating ${_bashrc} and ${_zshrc}..."
    if [[ "$(cat ${_bashrc})" != *"$1"* ]]; then
      echo -e "$1" >> "${_bashrc}"
    fi
    if [ -f "${_zshrc}" ] && [[ "$(cat ${_zshrc})" != *"$1"* ]]; then
      echo -e "$1" >> "${_zshrc}"
    fi
  fi
}

# Update the package manager cache
pkg_mgr_update() {
  # Make sure we have an adjusted ID
  [[ -z "${DISTRO:-}" ]] && check_distro
  # Make sure we have a package manager command
  [[ -z "${PKG_MGR_CMD:-}" ]] && setup_install_and_pkg_mgr_cmd

  case $DISTRO in
    debian)
      if [ "$(find /var/lib/apt/lists/* 2>/dev/null | wc -l)" = "0" ]; then
        echo "Running apt-get update..."
        ${PKG_MGR_CMD} update -y
      fi
      ;;
    rhel)
      if [ ${PKG_MGR_CMD} = "microdnf" ]; then
        if [ "$(ls /var/cache/yum/* 2>/dev/null | wc -l)" = 0 ]; then
          echo "Running ${PKG_MGR_CMD} makecache ..."
          ${PKG_MGR_CMD} makecache
        fi
      else
        if [ "$(ls /var/cache/${PKG_MGR_CMD}/* 2>/dev/null | wc -l)" = 0 ]; then
          echo "Running ${PKG_MGR_CMD} check-update ..."
          set +e
            stderr_messages=$(${PKG_MGR_CMD} -q check-update 2>&1)
            rc=$?
            # centos 7 sometimes returns a status of 100 when it apears to work.
            if [ $rc != 0 ] && [ $rc != 100 ]; then
              echo "(Error) ${PKG_MGR_CMD} check-update produced the following error message(s):"
              echo "${stderr_messages}"
              exit 1
            fi
          set -e
        fi
      fi
      ;;
  esac
}

# Checks if packages are installed and installs them if not
check_packages() {
  # Make sure we have an adjusted ID
  [[ -z "${DISTRO:-}" ]] && check_distro
  # Make sure we have an install command
  [[ -z "${INSTALL_CMD:-}" ]] && setup_install_and_pkg_mgr_cmd

  case ${DISTRO} in
    debian)
      if ! dpkg -s "$@" > /dev/null 2>&1; then
        pkg_mgr_update
        ${INSTALL_CMD} "$@"
      fi
      ;;
    rhel)
      if ! rpm -q "$@" > /dev/null 2>&1; then
        pkg_mgr_update
        ${INSTALL_CMD} "$@"
      fi
      ;;
  esac
}

# Determine the appropriate non-root user (and set the USERNAME global variable)
set_username() {
  # Mariner does not have awk installed by default, this can cause
  # problems if username is auto*
  if ! type awk >/dev/null 2>&1; then
    check_packages awk
  fi

  if [ "${USERNAME}" = "auto" ] || [ "${USERNAME}" = "automatic" ]; then
    _set2globals USERNAME ""
    POSSIBLE_USERS=("vscode" "node" "codespace" "$(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)")
    for CURRENT_USER in "${POSSIBLE_USERS[@]}"; do
      if id -u "${CURRENT_USER}" > /dev/null 2>&1; then
        _set2globals USERNAME "${CURRENT_USER}"
        break
      fi
    done
    if [ "${USERNAME}" = "" ]; then
      _set2globals USERNAME root
    fi
  elif [ "${USERNAME}" = "none" ] || ! id -u ${USERNAME} > /dev/null 2>&1; then
    _set2globals USERNAME root
  fi
}

# Run a command as the non-root user
sudo_if() {
  # Make sure we have a username
  [[ -z "${USERNAME:-}" ]] && set_username

  COMMAND="$*"
  if [ "$(id -u)" -eq 0 ] && [ "$USERNAME" != "root" ]; then
    su - "$USERNAME" -c "$COMMAND" 2>&1
  else
    $COMMAND 2>&1
  fi
}
