#!/bin/sh

CONTAINER_NAME=tsrain
CONTAINER_CID_PATH=/var/run/$CONTAINER_NAME.cid
TSRAIN_HOME=/opt/tsrain
TSRAIN_PKI_PATH=${TSRAIN_HOME}/pki
TSRAIN_CREDS_PATH="/var/opt/tsrain/services/${CONTAINER_NAME}/credentials.json"
TSRAIN_MAILBOX_PASSWORD=Password123!
RAINLOOP_DEFAULT_ADMIN_PASSWORD_PATH="/var/opt/tsrain/services/${CONTAINER_NAME}/rainloop-default-admin-password.txt"

if [ -f $CONTAINER_CID_PATH ]; then
  CONTAINER_ID=`docker container ls -q -f "name=${CONTAINER_NAME}"`
  if [ ! -z "${CONTAINER_ID}" ]; then
    echo $CONTAINER_NAME is already running.
    exit 1
  fi
fi

cd `dirname $0`

LATEST_TAG=`curl -s https://registry.hub.docker.com/v2/repositories/spearmint/tsrain/tags | jq -r '.results[].name' | sort -r --version-sort | head -1`

if [ -z "${LATEST_TAG}" ]; then
  TSRAIN_IMAGE=`docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "^spearmint/tsrain:" | sort -r | head -1`
else
  TSRAIN_IMAGE=spearmint/tsrain:${LATEST_TAG}
fi

TSRAIN_CONTAINER_ID=`docker container ls -q -f "name=${CONTAINER_NAME}"`
if [ -z "${TSRAIN_CONTAINER_ID}" ]; then
  mkdir -p `dirname "${TSRAIN_CREDS_PATH}"`

  if [ ! -f ${TSRAIN_CREDS_PATH} ]; then
    jq --arg password "${MAILBOX_PASSWORD}" -n '."*".password = $password' > ${TSRAIN_CREDS_PATH}
  fi
  chmod 600 ${TSRAIN_CREDS_PATH}

  RAINLOOP_DEFAULT_ADMIN_PASSWORD=`openssl rand -base64 24`
  echo ${RAINLOOP_DEFAULT_ADMIN_PASSWORD} > ${RAINLOOP_DEFAULT_ADMIN_PASSWORD_PATH}
  chmod 600 ${RAINLOOP_DEFAULT_ADMIN_PASSWORD_PATH}

  export RAINLOOP_DEFAULT_ADMIN_PASSWORD
  TSRAIN_CONTAINER_ID=`docker container run --rm --memory 384m --memory-swap 2g -d \
    -p 25:25 -p 80:88 -p 143:143 -p 443:443 -p 465:465 -p 993:993 \
    --name "${CONTAINER_NAME}" \
    -e RAINLOOP_DEFAULT_ADMIN_PASSWORD \
    --mount "type=bind,source=${TSRAIN_PKI_PATH},target=/usr/local/etc/pki" \
    --mount "type=bind,source=${TSRAIN_CREDS_PATH},target=/var/opt/testserv/credentials.json" \
    "${TSRAIN_IMAGE}"`

  if [ $? -eq 0 -a ! -z "${TSRAIN_CONTAINER_ID}" ]; then
    echo "container ${CONTAINER_NAME} has been started - ${TSRAIN_CONTAINER_ID}"
    echo ${TSRAIN_CONTAINER_ID} > ${CONTAINER_CID_PATH}
  else
    echo "failed to start the container - ${CONTAINER_NAME}."
    exit 1
  fi
else
  echo "container ${CONTAINER_NAME} is already active"
  exit 1
fi
