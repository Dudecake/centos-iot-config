#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" >&2
    exit 1
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"
KEY=${KEY:-920498D5E1E4D38C258A1AE623FE6D6C9114BC76}
DIST_NAME=iot
DIST_PATH=${DIST_PATH:-/srv/http/ckoomen.eu/ostree/iot}
CACHE_PATH=${CACHE_PATH:-/var/cache/rpm-ostree/centos/${DIST_NAME}}
MACHINE="$(uname -m)"

set -e
if [[ ${MACHINE} != "x86_64" && ${MACHINE} != "aarch64" && ${MACHINE} != "ppc64le" ]]; then
  echo "Invalid arch ${MACHINE}" >&2
  exit 1
fi

[[ ! -z ${DRYRUN} ]] && exit 0
[[ ! -d "${CACHE_PATH}" ]] && mkdir -p "${CACHE_PATH}"
if [[ ! -d "${DIST_PATH}/tmp" ]]; then
  mkdir -p ${DIST_PATH}
  ostree init --repo="${DIST_PATH}" --mode=archive
fi
if [[ -f "${DIST_PATH}/refs/heads/centos/8/${MACHINE}/${DIST_NAME}" ]]; then
  NEW_REPO=1
fi
cd ${DIR}
rpm-ostree compose tree --repo="${DIST_PATH}" --cachedir="${CACHE_PATH}" "${DIR}/centos-iot.yaml" --unified-core
if [[ -z "${NEW_REPO}" ]]; then
  ostree --repo="${DIST_PATH}" prune --only-branch fedora/${FEDORA_VERSION}/${MACHINE}/${DIST_NAME} --depth=5
  ostree --repo="${DIST_PATH}" static-delta generate centos/8/${MACHINE}/${DIST_NAME}
fi
#ostree --repo="${DIST_PATH}" gpg-sign centos/8/${MACHINE}/${DIST_NAME} ${KEY}
ostree --repo="${DIST_PATH}" summary -u
# Deploy with
# ostree remote add centos-iot http://${URL}/ostree/iot
# ostree pull centos-iot:centos/8/${MACHINE}/${DIST_NAME}
# ostree admin deploy --os=centos-iot centos-iot:centos/8/${MACHINE}/${DIST_NAME}
