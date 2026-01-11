#!/bin/sh

usage_exit() {
  echo "Usage: $0 [-p [password]] [-0 [port0]] [-1 [port1]] [-2 [port2]] [tenant] [admock-url] [xmocky-url]" 1>&2
  echo "  e.g. $0 -p password -0 443 -1 6361 -2 3001 se-demo https://github.com/spearmin10/demo/raw/main/mocky/admock-ldif.zip https://github.com/spearmin10/demo/raw/main/mocky/xmocky.zip"
  exit 1
}

cd `dirname $0`

ZIP_PASSWORD=
PORT0=
PORT1=
PORT2=
while getopts p:0:1:2:n:h OPT
do
  case $OPT in
    p)  ZIP_PASSWORD=$OPTARG
        ;;
    0)  PORT0=$OPTARG
        ;;
    1)  PORT1=$OPTARG
        ;;
    2)  PORT2=$OPTARG
        ;;
    h)  usage_exit
        ;;
    \?) usage_exit
        ;;
  esac
done
shift  $(($OPTIND - 1))

if [ -z "${PORT0}" -a -z "${PORT1}" -a -z "${PORT2}" ]; then
  usage_exit
fi

if [ $# -ne 3 ]; then
  usage_exit
fi

TENANT=$1
ADMOCK_URL=$2
XMOCKY_URL=$3

MOCKY_HOME=/opt/mocky
TENANT_HOME="${MOCKY_HOME}/tenants/${TENANT}"

mkdir -p "${HOME_DIR}/admock/bin"
mkdir -p "${HOME_DIR}/admock/etc"
mkdir -p "${HOME_DIR}/xmocky/bin"
mkdir -p "${HOME_DIR}/xmocky/xmocky"

cp -f admock.py "${HOME_DIR}/admock/bin/"
cp -f admock.sh "${HOME_DIR}/admock/bin/"
cp -f xmocky.sh "${HOME_DIR}/xmocky/bin/"

curl -L -o /dev/shm/admock-download.zip "$ADMOCK_URL"
rm -rf /dev/shm/admock-download.tmp
7za x -aoa -p"${ZIP_PASSWORD}" -o/dev/shm/admock-download.tmp /dev/shm/admock-download.zip
for file in "/dev/shm/admock-download.tmp/*.ldif"
do
  cp -f $file "${HOME_DIR}/admock/etc/admock.ldif"
done
rm -rf /dev/shm/admock-download.tmp
rm -rf /dev/shm/admock-download.zip

curl -L -o /dev/shm/xmocky-download.zip "$XMOCKY_URL"
7za x -aoa -p"${ZIP_PASSWORD}" -o"${HOME_DIR}/xmocky/xmocky" /dev/shm/xmocky-download.zip
rm -rf /dev/shm/xmocky-download.zip

cat << __EOT__ >> /dev/shm/docker-compose-tenant.yml
services:
    ${TENANT}:
        image: spearmint/mocky-env:latest
        restart: always
        mem_limit: 384m
        volumes:
            - /opt/mocky/tenants/${TENANT}/admock:/opt/admock
            - /opt/mocky/tenants/${TENANT}/xmocky:/opt/xmocky
        ports:
__EOT__

if [ ! -z "${PORT0}" ]; then
  cat << __EOT__ >> /dev/shm/docker-compose-tenant.yml
            - "${PORT0}:443"
__EOT__
fi
if [ ! -z "${PORT1}" ]; then
  cat << __EOT__ >> /dev/shm/docker-compose-tenant.yml
            - "${PORT1}:443"
__EOT__
fi
if [ ! -z "${PORT2}" ]; then
  cat << __EOT__ >> /dev/shm/docker-compose-tenant.yml
            - "${PORT2}:443"
__EOT__
fi

touch ${MOCKY_HOME}/system/etc/docker-compose.yml
yq -i ea '. as $item ireduce ({}; . * $item )' ${MOCKY_HOME}/system/etc/docker-compose.yml /dev/shm/docker-compose-tenant.yml 
