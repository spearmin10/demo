#!/bin/sh

docker container ps -a --format '{{.ID}}:{{.Image}}' | grep -E ":spearmint/tsrain:" | while read line
do
  CONTAINER_ID=`echo $line | cut -d ":" -f1`
  CONTAINER_IMAGE=`echo $line | cut -d ":" -f2-`
  docker container stop ${CONTAINER_ID} > /dev/null 2>&1
done
