#!/bin/sh

CONTAINER_NAME=tsrain

CONTAINER_ID=`docker container ls -q -f "name=${CONTAINER_NAME}"`
if [ ! -z "${CONTAINER_ID}" ]; then
  docker container stop ${CONTAINER_ID} > /dev/null 2>&1
fi
exit 0
