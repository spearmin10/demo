#!/bin/sh

TSRAIN_HOME=/opt/tsrain
CONTAINER_NAME=tsrain
CONTAINER_CID_PATH=/var/run/$CONTAINER_NAME.cid

if [ -f $CONTAINER_CID_PATH ]; then
  CONTAINER_ID=`docker container ls -q -f "name=${CONTAINER_NAME}"`
  if [ ! -z "${CONTAINER_ID}" ]; then
    echo $CONTAINER_NAME is already running.
    exit 1
  fi
fi

$TSRAIN_HOME/bin/run-tsrain-docker.sh
if [ $? -eq 0 ]; then
  CONTAINER_ID=`docker container ls -q -f "name=${CONTAINER_NAME}"`
  if [ -z "${CONTAINER_ID}" ]; then
    exit 1
  fi
  echo ${CONTAINER_ID} > ${CONTAINER_CID_PATH}
fi