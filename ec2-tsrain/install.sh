#!/bin/sh

TSRAIN_HOME=/opt/tsrain
TSRAIN_PKI_DIR=${TSRAIN_HOME}/pki
TSRAIN_BIN_DIR=${TSRAIN_HOME}/bin

if [ "$(id -u)" -ne 0 ]; then
  echo "The script must be run as root"
  exit 1
fi

### Setup System
dnf install -y jq docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user
systemctl restart docker.service

cat << '__EOT__' > /etc/rc.d/rc.local
#!/bin/sh

## Create and enable a swap
SWAP_FILENAME=/swap.img
SWAP_SIZE=2g
rm -f ${SWAPFILENAME}
fallocate -l ${SWAP_SIZE} ${SWAP_FILENAME} && mkswap ${SWAP_FILENAME} && swapon ${SWAP_FILENAME}

## Enable zram
modprobe zram
echo lz4 > /sys/block/zram0/comp_algorithm
echo 2048M > /sys/block/zram0/disksize
mkswap /dev/zram0
swapon -p 5 /dev/zram0

__EOT__

chmod +x /etc/rc.d/rc.local

### Setup TSRAIN
mkdir -p ${TSRAIN_BIN_DIR}
cd ${TSRAIN_BIN_DIR}
for file in tsrain-start.sh tsrain-stop.sh
do
  rm -f ${file}
  curl -s -L -J -O https://github.com/spearmin10/demo/blob/main/ec2-tsrain/${file}?raw=true
  if [ $? -ne 0 ]; then
    echo "Failed to download ${file}."
    exit 1
  fi
  chmod +x ${file}
done

cat << __EOT__ > /etc/systemd/system/tsrain.service
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

### Setup SSL Frontend
mkdir -p ${TSRAIN_PKI_DIR}

openssl req \
 -newkey ec:<(openssl ecparam -name prime256v1) \
 -nodes \
 -subj "/C=JP/O=Spearmint/CN=TSRAIN Root CA" \
 -keyout ${TSRAIN_PKI_DIR}/tsrain-root.key.pem | \
  openssl x509 -req \
   -signkey ${TSRAIN_PKI_DIR}/tsrain-root.key.pem  \
   -days 730 \
   -extensions EXTS -extfile <(printf "[EXTS]\nkeyUsage=cRLSign,digitalSignature,keyCertSign\nbasicConstraints=CA:TRUE") \
   -out ${TSRAIN_PKI_DIR}/tsrain-root.cer.pem

openssl req \
 -newkey ec:<(openssl ecparam -name prime256v1) \
 -nodes \
 -subj "/C=JP/O=Spearmint/CN=TSRAIN Service" \
 -keyout ${TSRAIN_PKI_DIR}/tsrain-svc.key.pem | \
  openssl x509 -req \
   -CA ${TSRAIN_PKI_DIR}/tsrain-root.cer.pem \
   -CAkey ${TSRAIN_PKI_DIR}/tsrain-root.key.pem \
   -set_serial 0x$(openssl rand -hex 16) \
   -days 365 \
   -extensions EXTS -extfile <(printf "[EXTS]\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nbasicConstraints=CA:FALSE") \
   -out ${TSRAIN_PKI_DIR}/tsrain-svc.cer.pem

cat ${TSRAIN_PKI_DIR}/tsrain-svc.cer.pem ${TSRAIN_PKI_DIR}/tsrain-root.cer.pem > ${TSRAIN_PKI_DIR}/tsrain-svc.chain.pem

# chmod 600 ${TSRAIN_PKI_DIR}/*.key.pem

# Apply zram settings
echo "*** The system will reboot in 10 seconds. ***"
sleep 10
reboot
