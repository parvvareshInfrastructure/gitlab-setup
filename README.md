# GitLab CE Auto Installer (Ubuntu 22.04)

A simple one-command script to install **GitLab Community Edition** on **Ubuntu 22.04 (Jammy)**.  
Supports both **IP-based** and **domain-based** setups, with optional **HTTPS + Let’s Encrypt**.

---

##  Requirements
- Ubuntu 22.04 LTS (Jammy)
- Root or sudo privileges
- Public IP address
- (Optional) A valid domain name pointing to the server IP

---

##  Quick Start
```bash
sudo bash install_gitlab.sh
````

During installation:

* Enter your **server IP**
* Choose whether you have a **domain**
* Optionally enable **HTTPS + Let’s Encrypt**

---

##  Access GitLab

* Via IP:

  ```
  http://<SERVER_IP>
  ```
* Via domain:

  ```
  https://gitlab.<your-domain>
  ```

---

##  Login Credentials

View your initial root password:

```bash
sudo cat /etc/gitlab/initial_root_password
```

* **Username:** `root`
* **Password:** (value from file above)

---

##  Enable HTTPS Later

1. Point your domain to the server IP.
2. Edit:

   ```ruby
   # /etc/gitlab/gitlab.rb
   external_url "https://gitlab.yourdomain.tld"
   letsencrypt['enable'] = true
   letsencrypt['contact_emails'] = ['you@example.com']
   ```
3. Apply changes:

   ```bash
   sudo gitlab-ctl reconfigure
   ```

---

##  Useful Commands

```bash
sudo gitlab-ctl status
sudo gitlab-ctl reconfigure
sudo gitlab-ctl tail
sudo gitlab-rake gitlab:backup:create
```

> Backups are stored in `/var/opt/gitlab/backups/`.

---

**Author:** Your Name
**License:** MIT
**Tested on:** Ubuntu 22.04 LTS (amd64)

```
```
