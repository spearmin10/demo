#!/bin/sh

TSRAIN_HOME=/opt/tsrain
SERVICE_NAME=tsrain-pm
SERVICE_APP=$SERVICE_NAME.go
SERVICE_CFG_PATH=$TSRAIN_HOME/etc/$SERVICE_NAME.json
SERVICE_PID_PATH=/var/run/$SERVICE_NAME.pid
SERVICE_LOG_PATH=/var/log/$SERVICE_NAME.log

export GOCACHE=/root/gocache
export XDC_CACHE_HOME=/root/gocache

cd $TSRAIN_HOME/bin

if [ -f $SERVICE_PID_PATH ]; then
  $pid = `cat $SERVICE_PID_PATH` 2> /dev/null
  kill -0 $pid > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo $SERVICE_NAME is already running.
    exit 1
  fi
fi

echo $$> $SERVICE_PID_PATH
sudo go run $SERVICE_APP -f $SERVICE_CFG_PATH >> $SERVICE_LOG_PATH 2>&1
rm -f $SERVICE_PID_PATH
