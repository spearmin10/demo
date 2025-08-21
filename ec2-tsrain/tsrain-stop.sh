#!/bin/sh

TSRAIN_HOME=/opt/tsrain
CONTAINER_NAME=tsrain
CONTAINER_CID_PATH=/var/run/$CONTAINER_NAME.cid

${TSRAIN_HOME}/bin/stop-tsrain-docker.sh
rm -f ${CONTAINER_CID_PATH}
exit 0
