#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" >&2
    exit 1
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"
KEY=${KEY:-920498D5E1E4D38C258A1AE623FE6D6C9114BC76}
DIST_NAME=iot
DIST_PATH=${DIST_PATH:-/var/lib/ostree/dist}
CACHE_PATH=${CACHE_PATH:-/var/cache/ostree}
MACHINE="$(uname -m)"
ZFS_VERSION="${ZFS_VERSION:-0.8.6-1}"
UPDATE_REPO=${UPDATE_REPO:-0}

set -e
for dir in "${DIST_PATH}/" "${CACHE_PATH}/zfs" "${CACHE_PATH}/${DIST_NAME}/tmp"; do
  if [[ ! -d ${dir} ]]; then
    mkdir -p ${dir}
  fi
done
pushd "${CACHE_PATH}/zfs" > /dev/null
if [[ ! -f zfs-dkms-${ZFS_VERSION}.el8.src.rpm ]]; then
  UPDATE_REPO=1
  rm -rf ./*
  curl -L --remote-name-all http://download.zfsonlinux.org/epel/8.3/SRPMS/zfs{,-dkms}-${ZFS_VERSION}.el8.src.rpm
fi
if [[ ! -f zfs-${ZFS_VERSION}.el8.${MACHINE}.rpm || ${UPDATE_REPO} -ne 0 ]]; then
  mock -r centos-8-${MACHINE} rebuild zfs{,-dkms}-${ZFS_VERSION}.*.src.rpm --resultdir .
  createrepo .
fi
popd > /dev/null

if [[ ${MACHINE} == "x86_64" || ${MACHINE} == "aarch64" || ${MACHINE} == "ppc64le" ]]; then
  BASEARCH="${MACHINE}"
  [[ ${BASEARCH} == "x86_64" ]] && BASEARCH="amd64"
  [[ ${BASEARCH} == "aarch64" ]] && BASEARCH="arm64"
  echo "Checking latest Kubernetes version..." >&2
  KUBERNETES_RELEASE="$(curl -sSL https://dl.k8s.io/release/stable.txt)"
  echo "Latest version is ${KUBERNETES_RELEASE}" >&2
  if [[ ! -f kubernetes-server-linux-${BASEARCH}-${KUBERNETES_RELEASE}.tar.gz ]]; then
    [[ -f kubernetes-server-linux-*-*.tar.gz ]] || rm kubernetes-server-linux-*-*.tar.gz
    echo "Downloading latest Kubernetes version" >&2
    curl -L https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_RELEASE}/kubernetes-server-linux-${BASEARCH}.tar.gz -o kubernetes-server-linux-${BASEARCH}-${KUBERNETES_RELEASE}.tar.gz
    tar --strip-components=3 -xf kubernetes-server-linux-${BASEARCH}-${KUBERNETES_RELEASE}.tar.gz
  fi
  echo "Checking latest crictl version..." >&2
  CRICTL_RELEASE="$(curl -sS https://github.com/kubernetes-sigs/cri-tools/releases/latest | grep -oP 'v\d\.\d{2}\.\d')"
  echo "Latest version is ${CRICTL_RELEASE}" >&2
  if [[ ! -f crictl-${CRICTL_RELEASE}-linux-${BASEARCH}.tar.gz ]]; then
    [[ -f crictl-*-linux-*.tar.gz ]] || rm crictl-*-linux-*.tar.gz
    echo "Downloading latest crictl version" >&2
    curl -LO https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_RELEASE}/crictl-${CRICTL_RELEASE}-linux-${BASEARCH}.tar.gz
    tar -xf crictl-${CRICTL_RELEASE}-linux-${BASEARCH}.tar.gz
  fi
else
  echo "Invalid arch ${MACHINE}" >&2
  exit 1
fi

[[ ! -z ${DRYRUN} ]] && exit 0
if [[ ! -d "${DIST_PATH}/tmp" ]]; then
  ostree init --repo="${DIST_PATH}" --mode=archive
  NEW_REPO=1
fi
rm -rf ${DIST_PATH}/tmp/*.tmp
rpm-ostree compose tree --repo="${DIST_PATH}" --workdir "${CACHE_PATH}/${DIST_NAME}/tmp" "${DIR}/centos-iot.yaml"
if [[ -z "${NEW_REPO}" ]]; then
  ostree --repo="${DIST_PATH}" static-delta generate centos/8/${MACHINE}/${DIST_NAME}
fi
#ostree --repo="${DIST_PATH}" gpg-sign centos/8/${MACHINE}/${DIST_NAME} ${KEY}
ostree --repo="${DIST_PATH}" summary -u
# Deploy with
# ostree remote add centos-iot http://${URL}/ostree/iot
# ostree pull centos-iot:centos/8/${MACHINE}/${DIST_NAME}
# ostree admin deploy centos-iot:centos/8/${MACHINE}/${DIST_NAME}
