#!/bin/sh

TSRAIN_HOME=/opt/tsrain
CONTAINER_NAME=tsrain
SERVICE_CID_PATH=/var/run/$SERVICE_NAME.cid

if [ -f $SERVICE_CID_PATH ]; then
  CONTAINER_ID=`docker container ls -q -f "name=${CONTAINER_NAME}"`
  if [ ! -z "${CONTAINER_ID}" ]; then
    echo $SERVICE_NAME is already running.
    exit 1
  fi
fi

$TSRAIN_HOME/bin/run-tsrain-docker.sh
