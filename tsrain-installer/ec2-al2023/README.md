TSRAIN Email Service Installer
===========

Get Started
----------

### 1. Create a new instance from an Amazon machine image
Minimum system requirements:
 - Architecture: ARM 64-bits
   - Machine Image: Amazon Linux 2023
   - Instance Type: tg4.micro (or any instance type with at least 1 vCPU and 1GB of RAM)
   - Storage Size: 8 GB

 - Architecture: x86 64-bits
   - Machine Image: Amazon Linux 2023
   - Instance Type: t4.micro (or any instance type with at least 1 vCPU and 1GB of RAM)
   - Storage Size: 8 GB

### 2. Run install.sh on the instance

```
curl -s -L https://github.com/spearmin10/demo/blob/main/tsrain-installer/ec2-al2023/install.sh?raw=true | sudo sh
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
  - Server private key
    - /opt/tsrain/pki/tsrain-svc.key.pem
  - Server certificate
    - /opt/tsrain/pki/tsrain-svc.cer.pem
  - Server Certificate with intermediate and root CA certs
    - /opt/tsrain/pki/tsrain-svc.chain.pem
      - (This file should contain the server certificate, followed by any intermediate CA certificates, and then the root CA certificate, in that specific order.)

### 2. Restart the service.
  - sudo systemctl restart tsrain


Email Users and password
----------
All mailbox users in the TSRAIN instance share a single common password, and any password change made by one user is automatically applied to all users. When specifying a mailbox email address for login, you can use a wildcard address to access all mailboxes matching the pattern. The wildcard must include the `@` symbol to separate the user and domain parts; for example, `*@*` grants access to all mailboxes. Additionally, the special account `*` allows access to all mailboxes without specifying an email address.

Custom Installation: All Services on Port 443
----------
To support environments where only port 443/TCP is accessible due to firewalls or other restrictions, TSRAIN can serve WebMail (HTTPS), IMAPS, and SMTPS over a single port (443).
This is achieved by installing an additional service that inspects incoming connections on port 443, identifies the protocol, and dispatches the traffic to the appropriate backend service.

### Option 1: Enable During a New Installation
#### Run install.sh with the `-m` option:
```
curl -s -L https://github.com/spearmin10/demo/blob/main/tsrain-installer/ec2-al2023/install.sh?raw=true | sudo sh /dev/stdin -m
```

The instance will reboot after the installation is complete, and the services will start automatically.

### Option 2: Add to an Existing Installation
#### Run install-pm.sh
```
curl -s -L https://github.com/spearmin10/demo/blob/main/tsrain-installer/ec2-al2023/install-pm.sh?raw=true | sudo sh
```

### Service Ports

All standard service ports are available by default.
In addition, a protocol multiplexer runs on port 443, allowing access to SMTP, IMAP4, and TSRAIN WebMail (HTTPS) over a single port by detecting the protocol.

#### Accessing from Clients
The protocol multiplexer can identify the service based on a **client certificate** presented during the TLS handshake.
The installer automatically generates the following client certificates and private keys under `/opt/tsrain/pki/`:

* `tsrain-smtp-client.cer.pem` / `tsrain-smtp-client.key.pem`
* `tsrain-imap4-client.cer.pem` / `tsrain-imap4-client.key.pem`
* `tsrain-rainloop-client.cer.pem` / `tsrain-rainloop-client.key.pem`

Notes:
* For **IMAP4**, client certificate–based identification is **mandatory**.
* For **SMTP** and **WebMail (HTTPS)**, client certificates are **optional**. If not provided, the multiplexer identifies the target service based on the initial protocol behavior.

Managing TSRAIN Services
----------
TSRAIN services are managed using **systemd**.
There are two main services:

1. **`tsrain`** – controls all standard TSRAIN services (WebMail, SMTP, IMAP4).
2. **`tsrain-pm`** – protocol multiplexer for serving WebMail, SMTP, and IMAP4 on port 443.

#### Start the Services
```
sudo systemctl start tsrain
sudo systemctl start tsrain-pm
```

#### Stop the Services

```bash
sudo systemctl stop tsrain
sudo systemctl stop tsrain-pm
```

#### Restart the Services
```
sudo systemctl restart tsrain
sudo systemctl restart tsrain-pm
```

Licensing
----------
### Webmail Frontend
TSRAIN uses [RainLoop Webmail (Community Edition)](https://www.rainloop.net/) as its webmail frontend.  
RainLoop Webmail (Community Edition) is released under the [GNU Affero General Public License, Version 3 (AGPLv3)](http://www.gnu.org/licenses/agpl-3.0.html).  
For further details about licensing and disclaimers, please refer to the official RainLoop website.




