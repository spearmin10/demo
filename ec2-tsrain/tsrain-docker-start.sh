#!/bin/sh

usage_exit() {
  echo "Usage: $0 [-n container-suffix] [-r] [-m] [-a] [-h]" 1>&2
  exit 1
}

cd `dirname $0`

CONTAINER_NAME=tsrain
CONTAINER_SUFFIX=
RESTART_SERVICE=0
MAILBOX_PASSWORD=Password123!
RAINLOOP_DEFAULT_ADMIN_PASSWORD=
PKI_PATH=/var/opt/tsrain/pki

while getopts n:m:a:rh OPT
do
  case $OPT in
    n)  CONTAINER_SUFFIX=$OPTARG
        ;;
    r)  RESTART_SERVICE=1
        ;;
    m)  read -sp "TSRAIN MailBox Password: " MAILBOX_PASSWORD
        ;;
    a)  read -sp "TSRAIN Admin Password: " RAINLOOP_DEFAULT_ADMIN_PASSWORD
        ;;
    h)  usage_exit
        ;;
    \?) usage_exit
        ;;
  esac
done

LATEST_TAG=`curl -s https://registry.hub.docker.com/v2/repositories/spearmint/tsrain/tags | jq -r '.results[].name' | sort -r --version-sort | head -1`

if [ ! -z "${CONTAINER_SUFFIX}" ]; then
  CONTAINER_NAME="${CONTAINER_NAME}-${CONTAINER_SUFFIX}"
fi
CREDS_PATH="/var/opt/tsrain/services/${CONTAINER_NAME}/credentials.json"

if [ -z "${LATEST_TAG}" ]; then
  TSRAIN_IMAGE=`docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "^spearmint/tsrain:" | sort -r | head -1`
else
  TSRAIN_IMAGE=spearmint/tsrain:${LATEST_TAG}
fi

TSRAIN_CONTAINER_ID=`docker container ls -q -f "name=${CONTAINER_NAME}"`
if [ -z "${TSRAIN_CONTAINER_ID}" ]; then
  mkdir -p `dirname "${CREDS_PATH}"`

  if [ ! -f ${CREDS_PATH} ]; then
    jq --arg password "${MAILBOX_PASSWORD}" -n '."*".password = $password' > ${CREDS_PATH}
  fi
  chmod 600 ${CREDS_PATH}

  if [ -z "${RAINLOOP_DEFAULT_ADMIN_PASSWORD}" ]; then
    RAINLOOP_DEFAULT_ADMIN_PASSWORD=`openssl rand -base64 24`
    RAINLOOP_DEFAULT_ADMIN_PASSWORD_PATH="/var/opt/tsrain/services/${CONTAINER_NAME}/rainloop-default-admin-password.txt"
    echo ${RAINLOOP_DEFAULT_ADMIN_PASSWORD} > ${RAINLOOP_DEFAULT_ADMIN_PASSWORD_PATH}
    chmod 600 ${RAINLOOP_DEFAULT_ADMIN_PASSWORD_PATH}
  fi

  export RAINLOOP_DEFAULT_ADMIN_PASSWORD
  TSRAIN_CONTAINER_ID=`docker container run --rm --memory 384m --memory-swap 2g -d -p "25:25" -p "80:80" -p "143:143" \
    --name "${CONTAINER_NAME}" \
    -e RAINLOOP_DEFAULT_ADMIN_PASSWORD \
    --mount "type=bind,source=${PKI_PATH},target=/usr/local/etc/pki" \
    --mount "type=bind,source=${CREDS_PATH},target=/var/opt/testserv/credentials.json" \
    "${TSRAIN_IMAGE}"`

  if [ $? -eq 0 -a ! -z "${TSRAIN_CONTAINER_ID}" ]; then
    echo "container ${CONTAINER_NAME} has been started - ${TSRAIN_CONTAINER_ID}"
  else
    echo "failed to start the container - ${CONTAINER_NAME}."
    exit 1
  fi
elif [ ${RESTART_SERVICE} -eq 1 ]; then
  docker container restart ${TSRAIN_CONTAINER_ID}
  if [ $? -eq 0 ]; then
    echo "container ${CONTAINER_NAME} has been restarted."
  else
    echo "failed to restart the container - ${CONTAINER_NAME}."
    exit 1
  fi
else
  echo "container ${CONTAINER_NAME} is already active"
  exit 1
fi

exit 0
