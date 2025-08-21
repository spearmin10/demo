#!/bin/sh

### Setup System
dnf install -y jq docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user
systemctl restart docker.service

cat << '__EOT__' > /etc/rc.d/rc.local
#!/bin/sh

###
## Create and enable a swap
###
SWAPFILENAME=/swap.img
SIZE=2g
rm -f $SWAPFILENAME
fallocate -l $SIZE $SWAPFILENAME && mkswap $SWAPFILENAME && swapon $SWAPFILENAME

###
## Enable zram
###
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
for file in run-tsrain-docker.sh stop-tsrain-dockers.sh tsrain-start.sh tsrain-stop.sh
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
dnf install -y stunnel

TSRAIN_PKI_DIR=/var/opt/tsrain/pki
mkdir -p ${TSRAIN_PKI_DIR}

openssl req -nodes -new -x509 \
 -days 730 \
 -subj "/C=JP/O=Cortex/CN=TSRAIN Root CA" \
 -newkey ec:<(openssl ecparam -name prime256v1) \
 -keyout ${TSRAIN_PKI_DIR}/tsrain-ca.key.pem \
 -out ${TSRAIN_PKI_DIR}/tsrain-ca.cer.pem

openssl req -new -nodes -x509 \
 -subj "/C=JP/O=Cortex/CN=TSRAIN Service" \
 -newkey ec:<(openssl ecparam -name prime256v1) \
 -keyout ${TSRAIN_PKI_DIR}/tsrain-svc.key.pem \
 -days 365 \
 -CA ${TSRAIN_PKI_DIR}/tsrain-ca.cer.pem \
 -CAkey ${TSRAIN_PKI_DIR}/tsrain-ca.key.pem \
 -out ${TSRAIN_PKI_DIR}/tsrain-svc.cer.pem

chmod 600 ${TSRAIN_PKI_DIR}/*.key.pem

cat << __EOT__ > /etc/stunnel/stunnel.conf
[tsrain-web]
accept  = 443
connect = 80
CAFile = ${TSRAIN_PKI_DIR}/tsrain-ca.cer.pem
cert = ${TSRAIN_PKI_DIR}/tsrain-svc.cer.pem
key = ${TSRAIN_PKI_DIR}/tsrain-svc.key.pem

[tsrain-smtps]
accept  = 465
connect = 25
CAFile = ${TSRAIN_PKI_DIR}/tsrain-ca.cer.pem
cert = ${TSRAIN_PKI_DIR}/tsrain-svc.cer.pem
key = ${TSRAIN_PKI_DIR}/tsrain-svc.key.pem

[tsrain-imap4-tls]
accept  = 993
connect = 143
CAFile = ${TSRAIN_PKI_DIR}/tsrain-ca.cer.pem
cert = ${TSRAIN_PKI_DIR}/tsrain-svc.cer.pem
key = ${TSRAIN_PKI_DIR}/tsrain-svc.key.pem

__EOT__

systemctl enable stunnel

systemctl start tsrain
systemctl start stunnel

# Apply zram settings
echo "*** The system will reboot in 10 seconds. ***"
sleep 10
reboot
