#!/usr/bin/env bash

set -e

#
# Configurable variables
#

DOCKER_TAG="v27.5.1"
DOCKER_VERSION="v27.5.1.m"
DOCKER_DATE="20250208"

#
# Architecture or file detection
#

if [ -f "$1" ]; then
  echo "Will use specified local file ${1}"
  DOCKER_FILE="$(realpath "${1}")"
elif [ "$1" == "uninstall" ] then;
  UNINSTALL=1
  echo "Uninstall everything including docker data"
else

  UNAME="${2:-$(uname -m)}"
  if [ -z "${UNAME##*x86_64*}" ]; then
    XARCH="amd64"
  elif [ -z "${UNAME##*aarch64*}" ]; then
    XARCH="arm64"
  elif [ -z "${UNAME##*armv[7-8]*}" ]; then
    XARCH="armhf"
  elif [ -z "${UNAME##*armv6*}" ]; then
    XARCH="armel"
  else
    echo "Cannot convert architecture from 'uname -m', using it directly"
    XARCH="${UNAME}"
  fi

  DOCKER_FILE="docker_${DOCKER_VERSION}_coreelec_${XARCH}_${DOCKER_DATE}.tar.xz"
  DOCKER_URL="https://github.com/deinferno/docker-coreelec/releases/download/${DOCKER_TAG}/${DOCKER_FILE}"
  DOCKER_FILE="/storage/${DOCKER_FILE}"

  echo "Will download docker from ${DOCKER_URL}"
fi

#
# Old version removal
#

if [ -d "/storage/.docker/bin" ]; then
  read -rp "Found an existing installation of coreelec-docker. Do you want to remove it and install newer coreelec-docker? [y/N]? " choice
  if [ "${choice}" == "y" ] || [ "${choice}" == "Y" ]; then
    echo "Uninstalling coreelec-docker"

    systemctl stop "service.system.docker.service"
    systemctl disable "service.system.docker.service"

    if $UNINSTALL; then
      echo "Removing /storage/.docker if exists"
      rm -rf /storage/.docker
    else
      rm -rf /storage/.docker/{bin,cli-plugins}
    fi
    rm -rf "/storage/.config/docker"
    rm -rf /storage/.config/systemd/{docker.service,service.system.docker.service,multi-user.target.wants/service.system.docker.service}
  else
    echo "Installation aborted."
    exit 1
  fi

fi

#
# Kodi addon version removal
#

if [ -f "/storage/.kodi/addons/service.system.docker/bin/dockerd" ]; then
  read -rp "Found a Docker package installed via kodi addon. Do you want to remove it and install corelec-docker 22.06 [y/N]? " choice
  if [ "$choice" == "y" ] || [ "$choice" == "Y" ]; then
      echo "Uninstalling Docker addon"

      systemctl stop "service.system.docker.service"
      systemctl disable "service.system.docker.service"
      rm -rf "/storage/.kodi/addons/service.system.docker"
      rm -rf "/storage/.kodi/userdata/addon_data/service.system.docker"
      rm -rf /storage/.kodi/addons/packages/service.system.docker*

      echo "delete from installed where addonID like '%docker%'; vacuum;" | sqlite3 "/storage/.kodi/userdata/Database/Addons33.db"
      echo "delete from texture where url like '%docker%'; vacuum;" | sqlite3 "/storage/.kodi/userdata/Database/Textures13.db"
  else
    echo "Installation aborted."
    exit 1
  fi
fi

if $UNINSTALL; then
  echo "Removing /storage/.docker if exists"
  rm -rf /storage/.docker
  echo "Uninstall is complete"
  exit 0
fi

#
# Download docker
#

if [ "${DOCKER_URL}" ]; then
  echo ""
  echo "DOCKER_URL: ${DOCKER_URL}"
  echo "Downloading docker. This may take a while."
  echo ""
  curl -L --fail "${DOCKER_URL}" -o "${DOCKER_FILE}"
fi

#
# Install docker
#

cd "/"
echo "Installing Docker"

tar Jxvf "${DOCKER_FILE}"

#
# Service configuration
#

echo "Configuring dockerd service"
echo "This may take a while"

systemctl daemon-reload
systemctl enable "service.system.docker.service"
systemctl restart "service.system.docker"

echo "Configuring PATH"
if [ "$(grep "PATH=/storage/.docker/bin" "/storage/.profile" 2>/dev/null)" == "" ]; then
  echo "export PATH=/storage/.docker/bin:\$PATH" >> "/storage/.profile"
  echo "docker PATH added to /storage/.profile"
fi

#
# Post install
#

read -rp "Do you want to remove downloaded artifact \"${DOCKER_FILE}\" [Y/n]? " choice
if [ "$choice" == "n" ] || [ "$choice" == "N" ]; then
  echo "Keeping ${DOCKER_FILE}"
else
  echo "Removing ${DOCKER_FILE}"
  rm "${DOCKER_FILE}"
fi

echo "Installation is almost finished. You have to reboot the system now to finish it."
echo "For more information about the package visit https://github.com/deinferno/docker-coreelec"

read -rp "Do you want to reboot the system now [y/N]? " choice
if [ "${choice}" == "y" ] || [ "${choice}" == "Y" ]; then
  shutdown -r now
fi
