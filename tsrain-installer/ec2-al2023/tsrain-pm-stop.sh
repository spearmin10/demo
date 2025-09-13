#!/bin/sh

killpstree(){
  local children=`ps --ppid $1 --no-heading | awk '{ print $1 }'`
  for child in $children
  do
    killpstree $child
  done
  kill $1
}

PID_PATH=/var/run/tsrain-pm.pid

if [ -f $PID_PATH ]; then
  pid=`cat $PID_PATH`
  kill -0 $pid > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    killpstree $pid
  fi
  rm -f $PID_PATH
fi
exit 0
