#!/bin/sh

TSRAIN_HOME=/opt/tsrain
TSRAIN_PKI_DIR=${TSRAIN_HOME}/pki
TSRAIN_BIN_DIR=${TSRAIN_HOME}/bin
TSRAIN_ETC_DIR=${TSRAIN_HOME}/etc

error_exit() {
  echo "Installation Failed." 1>&2
  exit 1
}

install_system_packages() {
  dnf install -y go || error_exit
}

download_files() {
  cd ${TSRAIN_BIN_DIR}
  for file in tsrain-pm.go tsrain-pm.json tsrain-pm-start.sh tsrain-pm-stop.sh
  do
    rm -f ${file}
    curl -s -L -J -O https://github.com/spearmin10/demo/blob/main/tsrain-installer/ec2-al2023/${file}?raw=true
    if [ $? -ne 0 ]; then
      echo "Failed to download ${file}."
      exit 1
    fi
    if [[ "$file" == *.sh ]]; then
      chmod +x ${file}
    fi
  done
}

install_tsrain_pm() {
  cat << __EOT__ > ${TSRAIN_ETC_DIR}/tsrain-pm.json || error_exit
{
  "services": {
    "smtp_port": 25,
    "imap4_port": 143,
    "rainloop_port": 80,
    "service_port": 443
  },
  "server_cert": {
    "private_key": "${TSRAIN_PKI_DIR}/server.key.pem",
    "certificate": "${TSRAIN_PKI_DIR}/server.chain.pem"
  },
  "client_ca_files": [
    "${TSRAIN_PKI_DIR}/tsrain-root.cer.pem"
  ]
}
__EOT__

  cd ${TSRAIN_PKI_DIR}

  for name in smtp imap4 rainloop
  do
    openssl req \
     -newkey ec:<(openssl ecparam -name prime256v1) \
     -nodes \
     -subj "/C=JP/O=Spearmint/CN=${name}-client" \
     -keyout tsrain-${name}-client.key.pem | \
      openssl x509 -req \
       -CA tsrain-root.cer.pem \
       -CAkey tsrain-root.key.pem \
       -set_serial 0x$(openssl rand -hex 16) \
       -days 365 \
       -extensions EXTS -extfile <(printf "[EXTS]\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=clientAuth\nbasicConstraints=CA:FALSE") \
       -out tsrain-${name}-client.cer.pem || error_exit
    chmod 600 tsrain-${name}-client.key.pem || error_exit
  done
}

install_tsrain_pm_service() {
  cat << __EOT__ > /etc/systemd/system/tsrain-pm.service || error_exit
[Unit]
Description = TSRAIN Protocol Multiplexer
After = tsrain.service

[Service]
ExecStart = ${TSRAIN_BIN_DIR}/tsrain-pm-start.sh
ExecStop = ${TSRAIN_BIN_DIR}/tsrain-pm-stop.sh
Restart = always
Type = simple

[Install]
WantedBy = multi-user.target
__EOT__

  systemctl enable tsrain-pm
}


if [ "$(id -u)" -ne 0 ]; then
  echo "The script must be run as root"
  exit 1
fi

if [ -z "$(systemctl status tsrain 2> /dev/null)" ]; then
  echo "TSRAIN must be installed before tsrain-pm."
fi

mkdir -p ${TSRAIN_BIN_DIR} || error_exit
mkdir -p ${TSRAIN_PKI_DIR} || error_exit
mkdir -p ${TSRAIN_ETC_DIR} || error_exit

### Setup System
install_system_packages

### Setup TSRAIN Protocol Multiplexer
download_files
issue_certificates
install_tsrain_pm
install_tsrain_pm_service

# Start the service
systemctl enable tsrain-pm
systemctl restart tsrain
systemctl restart tsrain-pm

echo "*** Installation Complete. ***"
