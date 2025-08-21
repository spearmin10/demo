#!/bin/sh

TSRAIN_HOME=/opt/tsrain
SERVICE_CID_PATH=/var/run/$SERVICE_NAME.cid

${TSRAIN_HOME}/bin/stop-tsrain-dockers.sh
rm -f ${SERVICE_CID_PATH}
exit 0
