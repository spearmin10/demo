TSRAIN Installer
===========

Get Started
----------

### 1. Create a new instance from an Amazon machine image
Minimum system requirements:
 - Architecture: ARM 64-bits
   - Machine Image: Amazon Linux 2023
   - Instance Type: tg4.micro (2 vCPU, 1GB RAM)
   - Storage Size: 8 GB

 - Architecture: x86 64-bits
   - Machine Image: Amazon Linux 2023
   - Instance Type: t4.micro (1 vCPU, 1GB RAM)
   - Storage Size: 8 GB

### 2. Run install.sh on the instance

```
curl -s -L https://github.com/spearmin10/demo/blob/main/ec2-tsrain/install.sh?raw=true | sudo sh
```

The instance will reboot after the installation is complete, and the services will start automatically.

### 3. Access the services

- TSRAIN Web Mail
  - https://&lt;your public ip&gt;/ or http://&lt;your public ip&gt;/
    - User ID: (any users)
    - Initial Password: Password123!
  - https://&lt;your public ip&gt;/?admin or http://&lt;your public ip&gt;/?admin
    - User ID: admin
    - Password: (See /var/opt/tsrain/services/tsrain/rainloop-default-admin-password.txt)

- TSRAIN SMTP Service
  - Port: 25

- TSRAIN SMTP Service (TLS)
  - Port: 465

- TSRAIN IMAP4 Service
  - Port: 143

- TSRAIN IMAP4 Service (TLS)
  - Port: 993


Use your own server certificate
----------


 - systemctl restart tsrain
 - systemctl restart stunnel
