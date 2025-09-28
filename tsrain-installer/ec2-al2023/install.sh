#!/bin/sh

CONTAINER_NAME=tsrain
TSRAIN_HOME=/opt/tsrain
TSRAIN_PKI_DIR=${TSRAIN_HOME}/pki
TSRAIN_ETC_DIR=${TSRAIN_HOME}/etc
TSRAIN_BIN_DIR=${TSRAIN_HOME}/bin
TSRAIN_CREDS_DIR=/var/opt/tsrain/services/${CONTAINER_NAME}
TSRAIN_MAILBOX_PASSWORD=TsrainDefault0!
RAINLOOP_CREDS_FILE=credentials.json
RAINLOOP_DEFAULT_ADMIN_PASSWORD_FILE=rainloop-default-admin-password.txt

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
  usermod -a -G docker ec2-user
  systemctl enable docker
  systemctl restart docker

  if [ ! -f /usr/bin/docker-compose ]; then
    COMPOSE_LATEST_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r '.tag_name')
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_LATEST_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
      -o /usr/local/bin/docker-compose || error_exit
    chmod +x /usr/local/bin/docker-compose
    ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
  fi
}

configure_file_swap() {
  if [ -z "$(swapon --show=TYPE | grep "^file$")" ]; then
    SWAP_SIZE=2g
    SWAP_FILEPATH=/swap.img
    rm -f ${SWAP_FILEPATH}
    fallocate -l ${SWAP_SIZE} ${SWAP_FILEPATH} && mkswap ${SWAP_FILEPATH} && swapon ${SWAP_FILEPATH}
    echo "${SWAP_FILEPATH} swap swap defaults 0 0" >> /etc/fstab
  fi
}

configure_zram_swap_service() {
  if [ -z "$(swapon --show=NAME | grep "^/dev/zram")" ]; then
    cat << '__EOT__' > /etc/systemd/system/zram-swap.service || error_exit
[Unit]
Description=zram swap
After=multi-user.target

[Service]
Type=oneshot
ExecStartPre=modprobe zram
ExecStartPre=sh -c 'echo lz4 > /sys/block/zram0/comp_algorithm'
ExecStartPre=sh -c 'echo 2048M > /sys/block/zram0/disksize'
ExecStartPre=mkswap /dev/zram0
ExecStart=swapon -p 5 /dev/zram0
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
__EOT__
    systemctl enable zram-swap
    systemctl start zram-swap
  fi
}

configire_tsrain_service() {
  RAINLOOP_CREDENTOALS_PATH="${TSRAIN_CREDS_DIR}/${RAINLOOP_CREDS_FILE}"
  RAINLOOP_DEFAULT_ADMIN_PASSWORD=`openssl rand -base64 24`

  cat << __EOT__ > ${TSRAIN_ETC_DIR}/.env || error_exit
TSRAIN_PKI_DIR=${TSRAIN_PKI_DIR}
RAINLOOP_CREDENTOALS_PATH=${RAINLOOP_CREDENTOALS_PATH}
RAINLOOP_DEFAULT_ADMIN_PASSWORD=${RAINLOOP_DEFAULT_ADMIN_PASSWORD}
__EOT__

  chmod 600 ${TSRAIN_ETC_DIR}/.env

  cat << '__EOT__' > ${TSRAIN_ETC_DIR}/docker-compose.yml || error_exit
services:
    tsrain:
        image: spearmint/tsrain:latest
        container_name: tsrain
        restart: always
        mem_limit: 384m
        memswap_limit: 2g
        environment:
            - RAINLOOP_DEFAULT_ADMIN_PASSWORD=${RAINLOOP_DEFAULT_ADMIN_PASSWORD}
        volumes:
            - ${TSRAIN_PKI_DIR}/server.key.pem:/usr/local/etc/pki/server.key.pem
            - ${TSRAIN_PKI_DIR}/server.chain.pem:/usr/local/etc/pki/server.chain.pem
            - ${RAINLOOP_CREDENTOALS_PATH}:/var/opt/testserv/credentials.json
        ports:
            - "25:25"
            - "80:80"
            - "143:143"
            - "443:444"
            - "465:465"
            - "993:993"
            - "4433:443"
__EOT__

  cat << __EOT__ > /etc/systemd/system/tsrain.service || error_exit
[Unit]
Description = TSRAIN Web Mail
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
WorkingDirectory=${TSRAIN_ETC_DIR}
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
RemainAfterExit=yes
TimeoutStartSec=0

[Install]
WantedBy = multi-user.target
__EOT__

  systemctl enable tsrain

  if [ ! -f ${RAINLOOP_CREDENTOALS_PATH} ]; then
    jq --arg password "${TSRAIN_MAILBOX_PASSWORD}" -n '."*".password = $password' > ${RAINLOOP_CREDENTOALS_PATH}
  fi
  chmod 600 ${RAINLOOP_CREDENTOALS_PATH}
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
       -extensions EXTS -extfile <(printf "[EXTS]\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=clientAuth\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid,issuer\nbasicConstraints=critical,CA:FALSE") \
       -out tsrain-${name}-client.cer.pem || error_exit
    chmod 600 tsrain-${name}-client.key.pem || error_exit
  done

  chmod 600 *.key.pem || error_exit
  rm -f server.cer.pem server.key.pem
  ln -sT tsrain-svc.cer.pem server.cer.pem || error_exit
  ln -sT tsrain-svc.key.pem server.key.pem || error_exit
  cat tsrain-svc.cer.pem tsrain-root.cer.pem > server.chain.pem || error_exit
}


if [ "$(id -u)" -ne 0 ]; then
  echo "The script must be run as root"
  exit 1
fi

mkdir -p ${TSRAIN_BIN_DIR} || error_exit
mkdir -p ${TSRAIN_ETC_DIR} || error_exit
mkdir -p ${TSRAIN_PKI_DIR} || error_exit
mkdir -p ${TSRAIN_CREDS_DIR} || error_exit

### Setup System
install_system_packages
configure_file_swap
configure_zram_swap_service

### Setup TSRAIN
configire_tsrain_service

### Setup SSL Frontend
issue_certificates

### Start TSRAIN
systemctl restart tsrain || error_exit

echo "*** Installation complete, and the TSRAIN service has started. ***"

