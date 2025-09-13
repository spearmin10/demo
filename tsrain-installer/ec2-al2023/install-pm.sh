#!/bin/sh

TSRAIN_HOME=/opt/tsrain
TSRAIN_PKI_DIR=${TSRAIN_HOME}/pki
TSRAIN_BIN_DIR=${TSRAIN_HOME}/bin
TSRAIN_ETC_DIR=${TSRAIN_HOME}/etc

if [ "$(id -u)" -ne 0 ]; then
  echo "The script must be run as root"
  exit 1
fi

if [ -z "$(systemctl status tsrain 2> /dev/null)" ]; then
  echo "TSRAIN must be installed before tsrain-pm."
fi


### Setup System
dnf install -y go

### Setup TSRAIN Protocol Multiplexer
mkdir -p ${TSRAIN_BIN_DIR}
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

cat << __EOT__ > /etc/systemd/system/tsrain-pm.service
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

mkdir -p ${TSRAIN_ETC_DIR}
cat << __EOT__ > ${TSRAIN_ETC_DIR}/tsrain-pm.json
{
  "services": {
    "smtp_port": 25,
    "imap4_port": 143,
    "rainloop_port": 80,
    "service_port": 443
  },
  "server_cert": {
    "private_key": "${TSRAIN_PKI_DIR}/tsrain-svc.key.pem",
    "certificate": "${TSRAIN_PKI_DIR}/tsrain-svc.chain.pem"
  },
  "client_ca_files": [
    "${TSRAIN_PKI_DIR}/tsrain-root.cer.pem"
  ]
}
__EOT__


### Issue client certificates
for name in smtp imap4 rainloop
do
  openssl req \
   -newkey ec:<(openssl ecparam -name prime256v1) \
   -nodes \
   -subj "/C=JP/O=Spearmint/CN=${name}-client" \
   -keyout ${TSRAIN_PKI_DIR}/tsrain-${name}-client.key.pem | \
    openssl x509 -req \
     -CA ${TSRAIN_PKI_DIR}/tsrain-root.cer.pem \
     -CAkey ${TSRAIN_PKI_DIR}/tsrain-root.key.pem \
     -set_serial 0x$(openssl rand -hex 16) \
     -days 365 \
     -extensions EXTS -extfile <(printf "[EXTS]\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=clientAuth\nbasicConstraints=CA:FALSE") \
     -out ${TSRAIN_PKI_DIR}/tsrain-${name}-client.cer.pem
  chmod 600 ${TSRAIN_PKI_DIR}/tsrain-${name}-client.key.pem
done

# Start the service
systemctl enable tsrain-pm
systemctl restart tsrain-pm

echo "*** Installation Completed. ***"
