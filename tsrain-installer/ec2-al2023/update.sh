#!/bin/sh

if [ "$(id -u)" -ne 0 ]; then
  echo "The script must be run as root"
  exit 1
fi

systemctl stop tsrain
docker pull spearmint/tsrain:latest
systemctl start tsrain
