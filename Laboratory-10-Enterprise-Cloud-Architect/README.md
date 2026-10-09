# Laboratory 10 – Enterprise Cloud Architect

**CCM101 – Cloud Computing** | **Project:** VaultCloud – Secure Multi-Tier Web Application
**Stack:** Nextcloud (app tier) + MariaDB (data tier) on Docker Compose, Ubuntu Server VM
**Prepared by:** [Member 1] | [Member 2] | [Member 3] | [Member 4]
**Section:** [Section] | **Instructor:** Jenkielyn C. Torres

## What this is

A private file-sharing cloud that is **persistent**, **hardened**, and **self-backing-up**:

| Requirement | How it is met |
|---|---|
| 1. Infrastructure & diagram | Windows host → VirtualBox → Ubuntu Server VM, NAT port forwarding (`architecture-diagram.png`) |
| 2. Deployment (IaC) | `docker-compose.yml` – Nextcloud + MariaDB, named volumes, health check |
| 3. Security | UFW default-deny, only SSH + web allowed; database on an internal-only Docker network |
| 4. Automation | `automation-script.sh` (health check + verified DB backup + retention) run by cron daily |
| 5. Documentation | `operational-manual.md`, `final-reflection.md`, this README |

## Files

```
Laboratory-10-Enterprise-Cloud-Architect/
├── README.md
├── architecture-diagram.png
├── docker-compose.yml
├── .env.example            # template for secrets (the real .env is NOT committed)
├── .gitignore
├── automation-script.sh
├── operational-manual.md
├── final-reflection.md
└── screenshots/            # evidence used in the manual
```

## Quick start

```bash
git clone https://github.com/<your-username>/<your-repo>.git
cd <your-repo>/Laboratory-10-Enterprise-Cloud-Architect
cp .env.example .env && nano .env      # set strong passwords
docker compose up -d
chmod +x automation-script.sh && ./automation-script.sh
```

Open `http://127.0.0.1:8080` (or the forwarded port of your environment).
Full procedures are in **operational-manual.md**.
