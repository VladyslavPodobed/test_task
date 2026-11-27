tools:
  terraform - provision infra on digitalocean
  ansible - configure infra
  docker-compose

steps:
  define dir structure
  finish terraform
    create droplet
    create ansible inventory
    input created resource's ip into inventory
  finish ansible
    dependencies
      install all dependencies like:
    user
      create user
      create ssh key pair
      grant sudo rights
      get priv key for youself so that you could ssh into the resource as one
    ssh hardening (implemented, see known issues below)
      drop-in config /etc/ssh/sshd_config.d/20-ssh-hardening.conf via the ssh role:
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PubkeyAuthentication yes
      AllowUsers deploy
      MaxAuthTries 3
      LoginGraceTime 30
      X11Forwarding no
      UsePAM no
    ufw
      only allow ssh & 80
      by default deny any incoming
      allow outgoing
        
  finish docker compose
    have ansible deploy docker var to remote host as it must run there

## what would've done differently

1. used some kind of secure storage for do_token instead of just using a shell var
2. created a separate root user for ansible instead of using `root`
3. use `host_key_checking = True` instead of `host_key_checking = False` in ansible.cfg - https://docs.ansible.com/projects/ansible/latest/inventory_guide/connection_details.html
4. generating ssh keys for generated users locally and transferring just the public key to remote host is a much better option, yet it requires providing ansible with root password and username of your own local root user account
would still try to implement that option though
5. containers shouldn't run as root, instead I should define USER in Dockerfile, compose I think also has user directive
6. manage terraform state in a better way, maybe by using terraform cloud (it's free), or upload to S3
managing state is a must if more than one person works on infra
7. 

# Rules for AI Agent

you are not allowed any writes unless explicitly approved
always show a draft before writing and wait for my approval


# Multi-Site Hosting on a VPS (DevOps Task)

Deploy 3 demo sites on a single DigitalOcean droplet: 2 static (HTML + Nginx)
and 1 PHP (server time + hostname), all behind one Nginx reverse proxy.

## Requirements

- 1 real VPS with public IP, reachable from the internet
- 3 sites, each in its own Docker container, managed by a single `docker-compose.yml`
- Containers auto-restart (crash + reboot), `restart: unless-stopped`
- Nginx reverse proxy routes by path (`/site1`, `/site2`, `/site3`); only the proxy listens on 80, site containers expose no ports
- UFW: only SSH (22) and HTTP (80) open; SSH key-based auth only
- Live URL, Git repo with step-by-step commits, screen recording of the full process

## Tools

- **Terraform** — provisions the droplet on DigitalOcean; on apply, a `null_resource`
  provisioner generates `ansible/inventory.yml` and populates it with the created droplet's IP,
  and the `ansible_playbook` resource (ansible/ansible provider) then runs
  `ansible/playbook.yml` against the droplet automatically
- **Ansible** — server configuration via roles (`ansible/playbook.yml`):
  - `dependencies` — installs Docker Engine + compose plugin from Docker's official apt repo
  - `user` — creates `test_user` with sudo group membership, generates an ed25519
    key pair on the remote, authorizes the public key
    (`ansible.posix.authorized_key`, `key: file://...` resolved on the managed
    host), and fetches the private key to the control node at
    `ansible/keys/<droplet_ip>/key` (chmod 600)
  - `ssh` — drops an sshd hardening config (`PasswordAuthentication no`,
    pubkey-only, `PermitRootLogin prohibit-password`, `AllowUsers test_user root`,
    `MaxAuthTries 3`, `LoginGraceTime 30`, no X11, no PAM) and restarts sshd
    via a handler when the config changes; depends on the `user` role
    (`meta/main.yml`) since it reuses its `user_name` var
  - `ufw` — installs UFW, allows 22/tcp (SSH) and 80/tcp (HTTP),
    sets default deny incoming / allow outgoing, enables it and reloads
  - `docker` — copies the whole `docker/` directory (compose file, site files,
    nginx configs) to the remote host at `/home/<user>/docker`, since compose
    must run there, and then runs `docker compose up -d` on the remote host
- **Docker Compose** — runs all containers (proxy + 3 sites)

## Docker Compose (`docker/`)

```
docker/
├── docker-compose.yml   4 services: reverse_proxy, website_one/two/three, php_fpm
├── nginx.conf           proxy config: routes /site{1,2,3} to the site containers
├── proxy-conf.d/        empty dir masking the image's stock default.conf (see gotcha)
├── site1/index.html     static
├── site2/index.html     static
└── site3/               PHP site: index.php + its own nginx server config
```

- only `reverse_proxy` publishes port 80; site containers are reachable only on
  the internal docker network
- routing: `location /siteN { proxy_pass http://website_N:80/; }` — the trailing
  `/` strips the `/siteN` prefix, so the backend receives `/` and serves its
  `index.html` (site3: `index.php` rendered via php_fpm)
- all containers use `restart: always` for crash/reboot recovery

### Gotcha: requests to `http://localhost/...` 404'd and never reached the backends

The `nginx:alpine` image ships a stock `/etc/nginx/conf.d/default.conf` with
`server_name localhost`. The proxy's `nginx.conf` includes `conf.d/*.conf`, so
browsing to `http://localhost/site1` sent `Host: localhost`, which exactly
matched the stock block (an exact server_name match beats the default server).
That block has no proxy locations — it looked for `/site1` in its own empty
docroot and returned 404 itself; the proxy_pass was never executed.
Fix: mount the empty `proxy-conf.d/` dir over `/etc/nginx/conf.d` in the
`reverse_proxy` service.

## Deploy steps

1. Terraform: `terraform apply` in `terraform/` creates the droplet, writes
   its IP into `ansible/inventory.yml`, and then runs the ansible playbook
   against the droplet automatically (via the `ansible_playbook` resource)
2. Ansible (optional, manual): `ansible-playbook -i inventory.yml playbook.yml`
   in `ansible/` does the same configuration as the terraform-driven run
3. Docker Compose: the `docker` ansible role copies `docker/` to the droplet
   and automatically runs `docker compose up -d` there, bringing up the
   proxy + all sites
4. Verify: sites reachable at `http://IP/site{1,2,3}`, container kill + reboot recovery

## Replicating on your own machine

Prerequisites:

- Terraform and Ansible installed locally
- A DigitalOcean account and API token (`do_token`)
- An SSH key uploaded to DigitalOcean named `test_task_ssh`
  (or change the name in `terraform/provider.tf`)

Steps:

```bash
# 1. clone the repo and provide your variables
git clone <repo-url> && cd <repo>

# 2. create terraform/terraform.tfvars with your values
#    (both vars must be set; the file is gitignored)
cat > terraform/terraform.tfvars <<EOF
do_token = "your_digitalocean_api_token"
pvt_key  = "$HOME/.ssh/id_ed25519"
EOF

# 3. provision the droplet; this also generates ansible/inventory.yml
cd terraform
terraform init
terraform plan -out=tf_plan
terraform apply tf_plan

# 4. install the ansible collection required by the playbook
#    (community.docker.docker_compose_v2) — without this the run fails
ansible-galaxy collection install community.docker

# 5. configure the server
cd ../ansible
ansible-playbook -i inventory.yml playbook.yml

# 6. start the sites (once docker-compose files are in place)
#    then verify:
curl http://<droplet_ip>/site1  # and /site2, /site3
```

Notes:

- `terraform/terraform.tfvars` holds your `do_token` and `pvt_key` — Terraform picks
  it up automatically, so no `-var` flags or `TF_VAR_` exports are needed; it is
  gitignored and must never be committed (alternatively export `TF_VAR_do_token`
  and `TF_VAR_pvt_key` instead)
- `ansible/inventory.yml` is generated by Terraform and gitignored — never edit it by hand
- the `ansible/ansible` terraform provider (v1.4.0, latest) generates its own temp
  inventory from `ansible_host` resources but silently drops their variables, so
  connection settings (IP, user, private key, relaxed host-key checking for the
  first connection) are passed via `extra_vars` on the `ansible_playbook` resource instead
- on a fresh Ubuntu 24.04 boot, unattended-upgrades can hold the apt lock when the
  playbook runs; the `dependencies` role waits for it (`DPkg::Lock::Timeout=600` and
  `lock_timeout` on the apt tasks)
- `ansible.cfg` disables host key checking for this demo (`host_key_checking = False`);
  see the "what would've done differently" section above
- `issues/` — troubleshooting notes for problems hit along the way
  (terraform errors, ansible gotchas, docker networking issues)
- the deploy user's private key is fetched to `ansible/keys/<droplet_ip>/key`
  (gitignored, `chmod 600` applied by the playbook) — connect with
  `ssh -i ansible/keys/<ip>/key test_user@<ip>`
