#!/bin/bash

MOCKY_HOME=/opt/mocky
MOCKY_ETC_DIR=${MOCKY_HOME}/system/etc
MOCKY_BIN_DIR=${MOCKY_HOME}/system/bin
MOCKY_RAW_URL=https://github.com/spearmin10/demo/raw/main/mocky/mocky
MOCKY_CONTENT_PASSWORD=
MOCKY_FQDN=
MOCKY_SUBDOMAIN=
MOCKY_DOMAIN=
LETSENCRYPT_USER=
DESEC_TOKEN=

usage_exit() {
  echo "Usage: $0 -p <content_password> [-u <letsencrypt_user> -t <desec_token> -f <mocky_fqdn>] [-h]" 1>&2
  exit 1
}

error_exit() {
  echo "Installation Failed." 1>&2
  exit 1
}

install_system_packages() {
  dnf install -y jq yq gettext docker p7zip cronie-noanacron || error_exit
  systemctl enable docker
  systemctl start docker
  usermod -a -G docker ec2-user
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
    SWAP_FILEPATH=/swapfile
    rm -f ${SWAP_FILEPATH}
    dd if=/dev/zero of=${SWAP_FILEPATH} bs=1M count=2048 || error_exit
    chmod 600 ${SWAP_FILEPATH} || error_exit
    mkswap ${SWAP_FILEPATH} || error_exit
    swapon ${SWAP_FILEPATH} || error_exit
    echo "${SWAP_FILEPATH} swap swap defaults 0 0" >> /etc/fstab || error_exit
  fi
}

configure_zram_swap_service() {
  if [ -z "$(swapon --show=NAME | grep "^/dev/zram")" ]; then
    cat << '__EOT__' > ${TSRAIN_BIN_DIR}/zram-swap.sh || error_exit
#!/bin/sh

ZRAM_PATH=/dev/zram0
if [ -f "${ZRAM_PATH}" ]; then
  echo "${ZRAM_PATH} already exists."
  exit 1
fi

modprobe -r zram
modprobe zram num_devices=1
if [ ! -f "${ZRAM_PATH}" ]; then
  echo "${ZRAM_PATH} is not found."
  exit 1
fi
zramctl "${ZRAM_PATH}" --size "$(($(grep -Po 'MemTotal:\s*\K\d+' /proc/meminfo)/2))KiB"
mkswap "${ZRAM_PATH}"
swapon "${ZRAM_PATH}"
__EOT__
    chmod +x ${TSRAIN_BIN_DIR}/zram-swap.sh

    cat << __EOT__ > /etc/systemd/system/zram-swap.service || error_exit
[Unit]
Description=zram swap
After=multi-user.target

[Service]
Type=oneshot
ExecStart=${TSRAIN_BIN_DIR}/zram-swap.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
__EOT__
    systemctl enable zram-swap
    systemctl start zram-swap
  fi
}

install_mocky() {
  mkdir -p "${MOCKY_BIN_DIR}"
  mkdir -p "${MOCKY_ETC_DIR}"

  for file in admock.py admock.sh xmocky.sh deploy-from-git-demo.sh ;
  do
    curl -L "${MOCKY_RAW_URL}/${file}" -o "${MOCKY_BIN_DIR}/${file}" || error_exit
  done
  chmod +x ${MOCKY_BIN_DIR}/*.sh
}

configire_mocky() {
  cat << __EOT__ > /etc/systemd/system/mocky.service || error_exit
[Unit]
Description = Mocky
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
WorkingDirectory=${MOCKY_ETC_DIR}
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
RemainAfterExit=yes
TimeoutStartSec=0

[Install]
WantedBy = multi-user.target
__EOT__

  systemctl enable mocky

  ${MOCKY_BIN_DIR}/deploy-from-git-demo.sh \
    -p "${MOCKY_CONTENT_PASSWORD}" \
    -0 443 -1 6361 -2 3001 \
    se-demo \
    "${MOCKY_RAW_URL}/data/admock-ldif.zip" \
    "${MOCKY_RAW_URL}/data/xmocky.zip"

  ${MOCKY_BIN_DIR}/deploy-from-git-demo.sh \
    -p "${MOCKY_CONTENT_PASSWORD}" \
    -0 6362 -1 3002 \
    cxj \
    "${MOCKY_RAW_URL}/data/admock-ldif-cxj.zip" \
    "${MOCKY_RAW_URL}/data/xmocky.zip"

  (crontab -l 2> /dev/null; echo "0 0 * * * systemctl restart mocky") | sort | uniq | crontab -
  systemctl enable crond
  systemctl restart crond
}

install_system_packages_for_certs() {
  dnf install -y jq yq python3.13 augeas-libs pip || error_exit
}

configure_mocky_dns() {
  #aws_token=`curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
  #public_ip=`curl -s -H "X-aws-ec2-metadata-token: $aws_token" http://169.254.169.254/latest/meta-data/public-ipv4`
  public_ip=`curl https://ipconfig.io/`
  if [ -z "${public_ip}" ]; then
    echo "Unable to get the public IP." 1>&2
    error_exit
  fi

  name=`curl https://desec.io/api/v1/domains/${MOCKY_DOMAIN}/rrsets/?subname=${MOCKY_SUBDOMAIN} \
    -H "Authorization: Token ${DESEC_TOKEN}" | jq -r '.[].name'`
  if [ -z "${name}" ]; then
    cat << __EOT__ | curl https://desec.io/api/v1/domains/${MOCKY_DOMAIN}/rrsets/ \
     --header "Authorization: Token ${DESEC_TOKEN}" \
     --header "Content-Type: application/json" --data @- | jq .
{
  "subname": "${MOCKY_SUBDOMAIN}",
  "type": "A",
  "ttl": 3600,
  "records": ["${public_ip}"]
}
__EOT__
  else
    cat << __EOT__ | curl -X PATCH https://desec.io/api/v1/domains/${MOCKY_DOMAIN}/rrsets/mocky/A/ \
     --header "Authorization: Token ${DESEC_TOKEN}" \
     --header "Content-Type: application/json" --data @- | jq .
{
  "records": ["${public_ip}"]
}
__EOT__
  fi
  
  # Wait for DNS propagation
  while true; do
    resolved_ip=`dig +short "$MOCKY_FQDN" | tail -n1`
    if [ "${resolved_ip}" == "${public_ip}" ]; then
      echo "DNS resolved correctly: $resolved_ip"
      break
    fi
    echo "Current: ${resolved_ip:-<not resolved>} (waiting...)"
    sleep 5
  done
}

configure_mocky_certs() {
  python3.13 -m venv /opt/certbot/ || error_exit
  /opt/certbot/bin/pip install --upgrade pip || error_exit
  /opt/certbot/bin/pip install certbot || error_exit
  ln -s /opt/certbot/bin/certbot /usr/bin/certbot
  certbot certonly --standalone --test-cert --agree-tos --dry-run -m ${LETSENCRYPT_USER} -d ${MOCKY_FQDN} || error_exit
  certbot certonly -n --standalone --agree-tos -m ${LETSENCRYPT_USER} -d ${MOCKY_FQDN} || error_exit

  yq -i "
    .services[].volumes |=
      (
        (. // []) +
        [
          \"/etc/letsencrypt/live/${MOCKY_FQDN}/fullchain.pem:/opt/mocky-fe/pki/server.chain.pem\",
          \"/etc/letsencrypt/live/${MOCKY_FQDN}/privkey.pem:/opt/mocky-fe/pki/server.key.pem\"
        ]
        | unique
      )
  " ${MOCKY_ETC_DIR}/docker-compose.yml
  
  (crontab -l 2> /dev/null; echo '0 23 * * * certbot renew --pre-hook "systemctl stop mocky" --post-hook "systemctl start mocky"') | sort | uniq | crontab -
  systemctl enable crond
  systemctl restart crond
}


if [ "$(id -u)" -ne 0 ]; then
  echo "The script must be run as root"
  exit 1
fi


while getopts p:l:t:f:h OPT
do
  case $OPT in
    p)  MOCKY_CONTENT_PASSWORD=$OPTARG
        ;;
    l)  LETSENCRYPT_USER=$OPTARG
        ;;
    t)  DESEC_TOKEN=$OPTARG
        ;;
    f)  MOCKY_FQDN=$OPTARG
        ;;
    h)  usage_exit
        ;;
    \?) usage_exit
        ;;
  esac
done
shift  $(($OPTIND - 1))

if [ -z "${MOCKY_CONTENT_PASSWORD}" ]; then
  usage_exit
fi
if [ ! -z "${LETSENCRYPT_USER}" -a ! -z "${DESEC_TOKEN}" -a ! -z "${MOCKY_FQDN}" ]; then
  MOCKY_SUBDOMAIN=`echo "$MOCKY_FQDN" | cut -d. -f1`
  MOCKY_DOMAIN=`echo "$MOCKY_FQDN" | cut -d. -f2-`
elif [ -z "${LETSENCRYPT_USER}" -a -z "${DESEC_TOKEN}" -a -z "${MOCKY_FQDN}" ]; then
  :
else
  usage_exit
fi

mkdir -p ${MOCKY_BIN_DIR} || error_exit
mkdir -p ${MOCKY_ETC_DIR} || error_exit

### Setup System
echo "Installing system packages..."
install_system_packages

echo "Configuring swap files..."
configure_file_swap

echo "Configuring zram swap..."
configure_zram_swap_service

### Setup mocky
echo "Installing mocky..."
install_mocky

echo "Configuring mocky..."
configire_mocky

if [ ! -z "${MOCKY_FQDN}" ]; then
  echo "Installing system packages..."
  install_system_packages_for_certs

  echo "Configuring DNS records..."
  configure_mocky_dns

  echo "Issuing server certificates..."
  configure_mocky_certs
fi

### Start mocky
echo "Starting the mocky service..."
systemctl restart mocky || error_exit

