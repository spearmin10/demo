#!/bin/sh

TSRAIN_HOME=/opt/tsrain
TSRAIN_PKI_DIR=${TSRAIN_HOME}/pki
TSRAIN_BIN_DIR=${TSRAIN_HOME}/bin

usage_exit() {
  echo "Usage: $0 [-m] [-h]" 1>&2
  exit 1
}

error_exit() {
  echo "Installation Failed." 1>&2
  exit 1
}

install_system_packages() {
  dnf install -y jq docker || error_exit
  systemctl start docker
  systemctl enable docker
  usermod -a -G docker ec2-user
  systemctl restart docker.service
}

configure_swap() {
  cat << '__EOT__' | tee ${TSRAIN_BIN_DIR}/swap-on.sh | sh
#!/bin/sh

SWAP_FILEPATH=/swap.img
if [ -z "$(swapon --show | grep "^${SWAP_FILEPATH}")" ]; then
  SWAP_SIZE=2g
  rm -f ${SWAP_FILEPATH}
  fallocate -l ${SWAP_SIZE} ${SWAP_FILEPATH} && mkswap ${SWAP_FILEPATH} && swapon ${SWAP_FILEPATH}
fi

SWAP_FILEPATH=/dev/zram0
if [ -z "$(swapon --show | grep "^${SWAP_FILEPATH}")" ]; then
  modprobe zram
  #zramctl -r ${SWAP_FILEPATH}
  #zramctl --find -a lz4 --size 512M --streams 4
  
  echo lz4 > /sys/block/zram0/comp_algorithm
  echo 2048M > /sys/block/zram0/disksize
  mkswap ${SWAP_FILEPATH} && swapon -p 5 ${SWAP_FILEPATH}
fi
__EOT__

  RC_LOCAL=/etc/rc.d/rc.local
  if [ ! -f ${RC_LOCAL} ]; then
    echo "#!/bin/sh" > ${RC_LOCAL}
    chmod +x ${RC_LOCAL}
  fi
  grep -qxF "${TSRAIN_BIN_DIR}/swap-on.sh" ${RC_LOCAL} || echo "${TSRAIN_BIN_DIR}/swap-on.sh" >> ${RC_LOCAL}
}

download_files() {
  cd ${TSRAIN_BIN_DIR}
  
  FILES="tsrain-start.sh tsrain-stop.sh"
  if [ ${PROTOCOL_MULTIPLEXER:-0} -eq 1 ]; then
    FILES="${FILES} install-pm.sh"
  fi

  for file in ${FILES}
  do
    rm -f ${file}
    curl -s -L -J -O https://github.com/spearmin10/demo/blob/main/tsrain-installer/ec2-al2023/${file}?raw=true
    if [ $? -ne 0 ]; then
      echo "Failed to download ${file}."
      exit 1
    fi
  done
  chmod +x *.sh
}

install_tsrain_service() {
  cat << __EOT__ > /etc/systemd/system/tsrain.service || error_exit
[Unit]
Description = TSRAIN Web Mail

[Service]
ExecStart = ${TSRAIN_BIN_DIR}/tsrain-start.sh
ExecStop = ${TSRAIN_BIN_DIR}/tsrain-stop.sh
Restart = always
Type = simple

[Install]
WantedBy = multi-user.target
__EOT__

  systemctl enable tsrain
}

issue_certificates() {
  cd ${TSRAIN_PKI_DIR}

  openssl req \
   -newkey ec:<(openssl ecparam -name prime256v1) \
   -nodes \
   -subj "/C=JP/O=Spearmint/CN=TSRAIN Root CA" \
   -keyout tsrain-root.key.pem | \
    openssl x509 -req \
     -signkey tsrain-root.key.pem  \
     -days 730 \
     -extensions EXTS -extfile <(printf "[EXTS]\nkeyUsage=critical,cRLSign,digitalSignature,keyCertSign\nsubjectKeyIdentifier=hash\nbasicConstraints=critical,CA:TRUE") \
     -out tsrain-root.cer.pem || error_exit

  openssl req \
   -newkey ec:<(openssl ecparam -name prime256v1) \
   -nodes \
   -subj "/C=JP/O=Spearmint/CN=TSRAIN Service" \
   -keyout tsrain-svc.key.pem | \
    openssl x509 -req \
     -CA tsrain-root.cer.pem \
     -CAkey tsrain-root.key.pem \
     -set_serial 0x$(openssl rand -hex 16) \
     -days 365 \
     -extensions EXTS -extfile <(printf "[EXTS]\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid,issuer\nbasicConstraints=critical,CA:FALSE") \
     -out tsrain-svc.cer.pem || error_exit

  chmod 600 *.key.pem || error_exit
  ln -sT tsrain-svc.cer.pem server.cer.pem || error_exit
  ln -sT tsrain-svc.key.pem server.key.pem || error_exit
  cat tsrain-svc.cer.pem tsrain-root.cer.pem > server.chain.pem || error_exit
}


if [ "$(id -u)" -ne 0 ]; then
  echo "The script must be run as root"
  exit 1
fi


PROTOCOL_MULTIPLEXER=${PROTOCOL_MULTIPLEXER:-0}
while getopts mh OPT
do
  case $OPT in
    m)  PROTOCOL_MULTIPLEXER=1
        ;;
    h)  usage_exit
        ;;
    \?) usage_exit
        ;;
  esac
done

mkdir -p ${TSRAIN_BIN_DIR} || error_exit
mkdir -p ${TSRAIN_PKI_DIR} || error_exit

### Setup System
install_system_packages
configure_swap

### Setup TSRAIN
download_files
install_tsrain_service

### Setup SSL Frontend
issue_certificates

### Install Protocol Multiplexer
if [ ${PROTOCOL_MULTIPLEXER} -eq 1 ]; then
  ${TSRAIN_BIN_DIR}/install-pm.sh
else
  echo "*** Installation Complete. ***"
fi
