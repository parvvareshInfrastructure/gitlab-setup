#!/usr/bin/env bash
set -euo pipefail

# GitLab CE installer for Ubuntu 22.04 (jammy)
# Supports: IP-only setup OR domain + HTTPS (Let's Encrypt)

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Please run as root: sudo bash $0"
    exit 1
  fi
}

prompt_inputs() {
  echo "=== GitLab CE Installer ==="
  read -rp "Enter SERVER PUBLIC IP (e.g., 31.184.130.229): " SERVER_IP
  [[ -n "${SERVER_IP:-}" ]] || { echo "IP is required."; exit 1; }

  read -rp "Do you already have a real domain to use? (y/N): " HAVE_DOMAIN
  HAVE_DOMAIN="${HAVE_DOMAIN,,}"
  if [[ "${HAVE_DOMAIN}" == "y" || "${HAVE_DOMAIN}" == "yes" ]]; then
    read -rp "Enter domain/hostname (e.g., gitlab.example.com): " HOSTNAME
    [[ -n "${HOSTNAME:-}" ]] || { echo "Hostname is required when using a domain."; exit 1; }

    echo "Choose protocol for external_url:"
    echo "  [1] HTTPS with Let's Encrypt (recommended)"
    echo "  [2] HTTP (no SSL for now)"
    read -rp "Choose 1 or 2 [default 1]: " PROTO_CHOICE
    PROTO_CHOICE="${PROTO_CHOICE:-1}"

    if [[ "${PROTO_CHOICE}" == "2" ]]; then
      USE_LETSENCRYPT="no"
      EXTERNAL_URL="http://${HOSTNAME}"
    else
      USE_LETSENCRYPT="yes"
      EXTERNAL_URL="https://${HOSTNAME}"
      read -rp "Contact email for Let's Encrypt (e.g., you@example.com): " LE_EMAIL
      [[ -n "${LE_EMAIL:-}" ]] || { echo "Email is required for Let's Encrypt."; exit 1; }
    fi
  else
    # IP-only mode (or local hostname)
    read -rp "Enter a local hostname (default: gitlab.local): " HOSTNAME
    HOSTNAME="${HOSTNAME:-gitlab.local}"
    USE_LETSENCRYPT="no"
    # Choose to expose via IP or hostname
    echo "Use EXTERNAL_URL as:"
    echo "  [1] http://${SERVER_IP}    (via IP)"
    echo "  [2] http://${HOSTNAME}     (via local hostname)"
    read -rp "Choose 1 or 2 [default 1]: " CHOICE
    CHOICE="${CHOICE:-1}"
    if [[ "${CHOICE}" == "2" ]]; then
      EXTERNAL_URL="http://${HOSTNAME}"
    else
      EXTERNAL_URL="http://${SERVER_IP}"
    fi
  fi

  echo
  echo "Summary:"
  echo "  SERVER_IP       = ${SERVER_IP}"
  echo "  HOSTNAME        = ${HOSTNAME}"
  echo "  EXTERNAL_URL    = ${EXTERNAL_URL}"
  echo "  LETS_ENCRYPT    = ${USE_LETSENCRYPT}"
  [[ "${USE_LETSENCRYPT}" == "yes" ]] && echo "  LE_EMAIL        = ${LE_EMAIL}"
  echo
  read -rp "Proceed with these settings? [y/N]: " CONFIRM
  [[ "${CONFIRM,,}" == "y" ]] || { echo "Aborted."; exit 1; }
}

prep_network() {
  # Optional sanity check: does hostname resolve to the server IP (if using domain)?
  if [[ "${USE_LETSENCRYPT}" == "yes" || "${EXTERNAL_URL}" == http*://${HOSTNAME}* ]]; then
    if command -v getent >/dev/null 2>&1; then
      RESOLVED_IP="$(getent hosts "${HOSTNAME}" | awk '{print $1}' | head -n1 || true)"
      if [[ -n "${RESOLVED_IP}" && "${RESOLVED_IP}" != "${SERVER_IP}" ]]; then
        echo "WARNING: ${HOSTNAME} resolves to ${RESOLVED_IP}, not ${SERVER_IP}."
        echo "Let's Encrypt requires the domain to resolve to this server."
        read -rp "Continue anyway? (y/N): " go
        [[ "${go,,}" == "y" ]] || exit 1
      fi
    fi
  fi

  # Open basic ports (UFW) if available
  if command -v ufw >/dev/null 2>&1; then
    ufw allow OpenSSH || true
    ufw allow 80/tcp || true
    ufw allow 443/tcp || true
  fi
}

setup_hostname_and_hosts() {
  echo ">> Setting system hostname to '${HOSTNAME}' ..."
  hostnamectl set-hostname "${HOSTNAME}"

  # Ensure /etc/hosts maps server IP to hostname (helps local resolution)
  if ! grep -Eq "^\s*${SERVER_IP}\s+.*\b${HOSTNAME}\b" /etc/hosts; then
    echo ">> Adding '${SERVER_IP} ${HOSTNAME} gitlab' to /etc/hosts"
    echo "${SERVER_IP} ${HOSTNAME} gitlab" >> /etc/hosts
  fi
}

apt_prep() {
  export DEBIAN_FRONTEND=noninteractive
  apt update
  apt upgrade -y
  apt install -y curl ca-certificates apt-transport-https gnupg lsb-release
}

add_gitlab_repo() {
  echo ">> Adding GitLab CE repository ..."
  curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash
  apt update
}

install_gitlab() {
  echo ">> Installing GitLab CE with EXTERNAL_URL='${EXTERNAL_URL}' ..."
  EXTERNAL_URL="${EXTERNAL_URL}" apt-get install -y gitlab-ce
}

configure_gitlab() {
  # If Let's Encrypt is requested, write into /etc/gitlab/gitlab.rb before reconfigure
  if [[ "${USE_LETSENCRYPT}" == "yes" ]]; then
    echo ">> Enabling Let's Encrypt in /etc/gitlab/gitlab.rb"
    # Ensure external_url is correct and LE is enabled
    if grep -q '^external_url' /etc/gitlab/gitlab.rb; then
      sed -i "s|^external_url .*|external_url \"${EXTERNAL_URL}\"|g" /etc/gitlab/gitlab.rb
    else
      echo "external_url \"${EXTERNAL_URL}\"" >> /etc/gitlab/gitlab.rb
    fi
    # Add/replace LE settings
    if grep -q "^letsencrypt\['enable'\]" /etc/gitlab/gitlab.rb; then
      sed -i "s|^letsencrypt\['enable'\].*|letsencrypt['enable'] = true|g" /etc/gitlab/gitlab.rb
    else
      echo "letsencrypt['enable'] = true" >> /etc/gitlab/gitlab.rb
    fi
    if grep -q "^letsencrypt\['contact_emails'\]" /etc/gitlab/gitlab.rb; then
      sed -i "s|^letsencrypt\['contact_emails'\].*|letsencrypt['contact_emails'] = ['${LE_EMAIL}']|g" /etc/gitlab/gitlab.rb
    else
      echo "letsencrypt['contact_emails'] = ['${LE_EMAIL}']" >> /etc/gitlab/gitlab.rb
    fi
  fi

  echo ">> gitlab-ctl reconfigure (this may take several minutes) ..."
  gitlab-ctl reconfigure

  echo ">> GitLab services:"
  gitlab-ctl status || true

  echo ">> Initial root password (valid for 24h after first reconfigure):"
  if [[ -f /etc/gitlab/initial_root_password ]]; then
    cat /etc/gitlab/initial_root_password
  else
    echo "File /etc/gitlab/initial_root_password not found."
    echo "Reset with: gitlab-rake \"gitlab:password:reset[root]\""
  fi
}

create_backup() {
  echo ">> Creating initial backup ..."
  gitlab-rake gitlab:backup:create
  echo "Backup location: /var/opt/gitlab/backups/"
}

post_notes() {
  echo
  echo "=============================================================="
  echo " GitLab is installed!"
  echo " Open in browser:"
  echo "   ${EXTERNAL_URL}"
  echo
  echo "If you used a local hostname and want to access from your laptop,"
  echo "add to your local hosts file:"
  echo "   ${SERVER_IP} ${HOSTNAME}"
  echo
  echo "To switch later to a real domain + HTTPS:"
  echo "  1) Point DNS: gitlab.yourdomain.tld -> ${SERVER_IP}"
  echo "  2) Edit /etc/gitlab/gitlab.rb:"
  echo "       external_url \"https://gitlab.yourdomain.tld\""
  echo "       letsencrypt['enable'] = true"
  echo "       letsencrypt['contact_emails'] = ['you@example.com']"
  echo "  3) Run: gitlab-ctl reconfigure"
  echo "=============================================================="
}

main() {
  require_root
  prompt_inputs
  prep_network
  setup_hostname_and_hosts
  apt_prep
  add_gitlab_repo
  install_gitlab
  configure_gitlab
  create_backup
  post_notes
}

main "$@"
