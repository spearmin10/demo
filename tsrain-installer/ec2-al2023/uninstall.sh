#!/bin/sh

TSRAIN_HOME=/opt/tsrain

if [ "$(id -u)" -ne 0 ]; then
  echo "The script must be run as root"
  exit 1
fi

systemctl stop tsrain 2> /dev/null
systemctl stop tsrain-pm 2> /dev/null
systemctl disable tsrain 2> /dev/null
systemctl disable tsrain-pm 2> /dev/null
rm -f /etc/systemd/system/tsrain.service 2> /dev/null
rm -f /etc/systemd/system/tsrain-pm.service 2> /dev/null
rm -rf "${TSRAIN_HOME}"
docker images spearmint/tsrain --format "{{.Repository}}:{{.Tag}}" | xargs -r docker rmi 2> /dev/null

echo "*** Uninstallation Finished. ***"
