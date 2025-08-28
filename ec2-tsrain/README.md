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

### 3. Open ports and access the services

Configure the inbound rules of the security group associated with your instance to allow access to the service ports. The ports used by the services are listed below, along with their access methods.

- TSRAIN Web Mail
  - https://&lt;your public ip&gt;/ or http://&lt;your public ip&gt;/
    - User ID: (any users)
    - Initial Password: TsrainDefault0!
  - https://&lt;your public ip&gt;/?admin or http://&lt;your public ip&gt;/?admin
    - User ID: admin
    - Password: (See /opt/tsrain/services/tsrain/rainloop-default-admin-password.txt)

- TSRAIN SMTP Service
  - Port: 25
  - STARTTLS is supported

- TSRAIN SMTP Service (TLS)
  - Port: 465

- TSRAIN IMAP4 Service
  - Port: 143
  - STARTTLS is supported

- TSRAIN IMAP4 Service (TLS)
  - Port: 993


Use your own server certificate
----------
### 1. Replace the certificate and private key
  - Server Certificate with intermediate and root CA certs
    - /opt/tsrain/pki/tsrain-svc.chain.pem
      - (This file should contain the server certificate, followed by any intermediate CA certificates, and then the root CA certificate, in that specific order.)
  - Server private key
    - /opt/tsrain/pki/tsrain-svc.key.pem

### 2. Restart the TLS transport service.
  - sudo systemctl restart stunnel


Email Users and password
----------
All mailbox users in the TSRAIN instance share a single common password, and any password change made by one user is automatically applied to all users. When specifying a mailbox email address for login, you can use a wildcard address to access all mailboxes matching the pattern. The wildcard must include the `@` symbol to separate the user and domain parts; for example, `*@*` grants access to all mailboxes. Additionally, the special account `*` allows access to all mailboxes without specifying an email address.


Licensing
----------
### Webmail Frontend
TSRAIN uses [RainLoop Webmail (Community Edition)](https://www.rainloop.net/) as its webmail frontend.  
RainLoop Webmail (Community Edition) is released under the [GNU Affero General Public License, Version 3 (AGPLv3)](http://www.gnu.org/licenses/agpl-3.0.html).  
For further details about licensing and disclaimers, please refer to the official RainLoop website.




