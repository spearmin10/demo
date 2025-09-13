#!/bin/sh

CONTAINER_NAME=tsrain
TSRAIN_HOME=/opt/tsrain
TSRAIN_PKI_PATH=${TSRAIN_HOME}/pki
TSRAIN_CREDS_PATH="/var/opt/tsrain/services/${CONTAINER_NAME}/credentials.json"
TSRAIN_MAILBOX_PASSWORD=TsrainDefault0!
RAINLOOP_DEFAULT_ADMIN_PASSWORD_PATH="/var/opt/tsrain/services/${CONTAINER_NAME}/rainloop-default-admin-password.txt"

cd `dirname $0`

LATEST_TAG=`curl -s https://registry.hub.docker.com/v2/repositories/spearmint/tsrain/tags | jq -r '.results[].name' | sort -r --version-sort | head -1`
if [ -z "${LATEST_TAG}" ]; then
  TSRAIN_IMAGE=`docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "^spearmint/tsrain:" | sort -r | head -1`
  if [ -z "${TSRAIN_IMAGE}" ]; then
    TSRAIN_IMAGE=spearmint/tsrain:latest
  fi
else
  TSRAIN_IMAGE=spearmint/tsrain:${LATEST_TAG}
fi

TSRAIN_CONTAINER_ID=`docker container ls -q -f "name=${CONTAINER_NAME}"`
if [ -z "${TSRAIN_CONTAINER_ID}" ]; then
  mkdir -p `dirname "${TSRAIN_CREDS_PATH}"`

  if [ ! -f ${TSRAIN_CREDS_PATH} ]; then
    jq --arg password "${TSRAIN_MAILBOX_PASSWORD}" -n '."*".password = $password' > ${TSRAIN_CREDS_PATH}
  fi
  chmod 600 ${TSRAIN_CREDS_PATH}

  RAINLOOP_DEFAULT_ADMIN_PASSWORD=`openssl rand -base64 24`
  echo ${RAINLOOP_DEFAULT_ADMIN_PASSWORD} > ${RAINLOOP_DEFAULT_ADMIN_PASSWORD_PATH}
  chmod 600 ${RAINLOOP_DEFAULT_ADMIN_PASSWORD_PATH}

  export RAINLOOP_DEFAULT_ADMIN_PASSWORD
  if [[ `systemctl is-enabled tsrain-pm 2> /dev/null` = "enabled" ]]; then
    PORT_MAP="-p 25:25 -p 80:80 -p 143:143 -p 465:465 -p 993:993"
  else
    PORT_MAP="-p 25:25 -p 80:80 -p 143:143 -p 443:443 -p 465:465 -p 993:993"
  fi
  docker container run --rm --memory 384m --memory-swap 2g \
    ${PORT_MAP} \
    --name "${CONTAINER_NAME}" \
    -e RAINLOOP_DEFAULT_ADMIN_PASSWORD \
    --mount "type=bind,source=${TSRAIN_PKI_PATH},target=/usr/local/etc/pki" \
    --mount "type=bind,source=${TSRAIN_CREDS_PATH},target=/var/opt/testserv/credentials.json" \
    "${TSRAIN_IMAGE}"7
else
  echo "container ${CONTAINER_NAME} is already active"
  exit 1
fi
