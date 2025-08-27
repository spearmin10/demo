#!/bin/sh

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
SWAPFILENAME=/swap.img
SIZE=2g
rm -f $SWAPFILENAME
fallocate -l $SIZE $SWAPFILENAME && mkswap $SWAPFILENAME && swapon $SWAPFILENAME

## Enable zram
modprobe zram
echo lz4 > /sys/block/zram0/comp_algorithm
echo 2048M > /sys/block/zram0/disksize
mkswap /dev/zram0
swapon -p 5 /dev/zram0

__EOT__

chmod +x /etc/rc.d/rc.local

### Setup TSRAIN
mkdir -p /opt/tsrain/bin
cd /opt/tsrain/bin
for file in tsrain-docker-start.sh tsrain-docker-stop.sh tsrain-start.sh tsrain-stop.sh
do
  curl -s -L -J -O https://github.com/spearmin10/demo/blob/main/ec2-tsrain/${file}?raw=true
  if [ $? -ne 0 ]; then
    echo "Failed to download ${file}."
    exit 1
  fi
  chmod +x ${file}
done

cat << '__EOT__' > /etc/systemd/system/tsrain.service
[Unit]
Description = TSRAIN Web Mail

[Service]
ExecStart = /opt/tsrain/bin/tsrain-start.sh
ExecStop = /opt/tsrain/bin/tsrain-stop.sh
Restart = always
Type = simple

[Install]
WantedBy = multi-user.target
__EOT__

systemctl enable tsrain

### Setup SSL Frontend
TSRAIN_PKI_DIR=/var/opt/tsrain/pki
mkdir -p ${TSRAIN_PKI_DIR}

openssl req \
 -newkey ec:<(openssl ecparam -name prime256v1) \
 -nodes \
 -subj "/C=JP/O=Cortex/CN=TSRAIN Root CA" \
 -keyout ${TSRAIN_PKI_DIR}/tsrain-root.key.pem | \
  openssl x509 -req \
   -signkey ${TSRAIN_PKI_DIR}/tsrain-root.key.pem  \
   -days 730 \
   -extensions EXTS -extfile <(printf "[EXTS]\nkeyUsage=cRLSign,digitalSignature,keyCertSign\nbasicConstraints=CA:TRUE") \
   -out ${TSRAIN_PKI_DIR}/tsrain-root.cer.pem

openssl req \
 -newkey ec:<(openssl ecparam -name prime256v1) \
 -nodes \
 -subj "/C=JP/O=Cortex/CN=TSRAIN Service" \
 -keyout ${TSRAIN_PKI_DIR}/tsrain-svc.key.pem | \
  openssl x509 -req \
   -CA ${TSRAIN_PKI_DIR}/tsrain-root.cer.pem \
   -CAkey ${TSRAIN_PKI_DIR}/tsrain-root.key.pem \
   -set_serial 0x$(openssl rand -hex 16) \
   -days 365 \
   -extensions EXTS -extfile <(printf "[EXTS]\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nbasicConstraints=CA:FALSE") \
   -out ${TSRAIN_PKI_DIR}/tsrainsvc.cer.pem

cat ${TSRAIN_PKI_DIR}/tsrain-svc.cer.pem ${TSRAIN_PKI_DIR}/tsrain-root.cer.pem > ${TSRAIN_PKI_DIR}/tsrain-svc.chain.pem

# chmod 600 ${TSRAIN_PKI_DIR}/*.key.pem

# Apply zram settings
echo "*** The system will reboot in 10 seconds. ***"
sleep 10
reboot
