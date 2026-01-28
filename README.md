# NYC Taxi Data Engineering Project

Project overview
----------------
This repository is a turnkey NYC Taxi data engineering pipeline designed as part of the learning process in the DataTalks Club 2026 Data Engineering Zoomcamp course. It may be classified as a small-scale analytics project on GCP's Always Free tier, as well as demonstrates the application of infrastructure as
code (Terraform), containerized services (Docker Compose), idempotent ingestion with
Python, and basic analytics in Postgres.

Goals:
- Reproducible: deployable with `terraform` and a single VM.
- Educational: clear, well-documented code suitable for fellow students and reviewers.
- Secure-by-default: firewall and IAM patterns that avoid accidental exposure.

Repository layout
-----------------
```
README.md
requirements.txt
 .env.example
docker/
	docker-compose.yaml
python/
	ingest_data.py
sql/
	create_user.sql
	init.sql
terraform/
	main.tf
	variables.tf
	outputs.tf
	terraform.tfvars
data/  # runtime, not committed
```

Quick setup (high level)
------------------------
1. Install `terraform` and `gcloud` and authenticate to your GCP project.
2. Copy `.env.example` to `.env` and fill in secrets (do NOT commit `.env`).
3. Edit `terraform/terraform.tfvars` and set the required fields including
	 `project`, `ssh_cidr` and `admin_cidr` (both must be narrow CIDRs; do not use 0.0.0.0/0).
4. Run the following to validate and plan:

```bash
cd terraform
terraform init
terraform validate
terraform plan -var-file=terraform.tfvars
```

When ready, apply:

```bash
terraform apply -var-file=terraform.tfvars -auto-approve
```

Important notes on security and Always Free
-----------------------------------------
- The Terraform configuration is designed to run on an Always Free VM (`f1-micro`).
- `ssh_cidr` and `admin_cidr` are required and must be set to a single trusted CIDR.
- PostgreSQL is intentionally not exposed publicly at the firewall level; pgAdmin
	is restricted to `admin_cidr`.
- Startup scripts do not print environment variables; `.env` is read with restrictive
	permissions on the VM.

Running locally (development)
-----------------------------
To run the stack on your workstation for development:

```bash
cp .env.example .env
# Edit .env with strong local credentials
cd docker
docker compose up -d

# Run ingestion manually (uses .env)
python3 python/ingest_data.py
```

Testing analytical queries
--------------------------
After ingestion, connect to Postgres and run the analytical queries in `README.md`.
Example queries for the assignment are included below and in the original README.

Developer / teaching notes
--------------------------
- `python/ingest_data.py` is written to be readable for learners: functions have
	docstrings, mapping logic is explicit, and chunked ingestion demonstrates
	memory-efficient processing using `pyarrow.dataset`.
- `sql/init.sql` contains schema definitions and helpful indexes for the analytical
	queries. These indexes are lightweight and appropriate for small datasets.
- `docker/docker-compose.yaml` documents port exposure and recommended resource
	considerations for Always Free VMs. By default the repo exposes `5432` and `8080`
	on the VM; firewall rules in `terraform/` restrict external access.

How to run the final validation (suggested checklist)
---------------------------------------------------
1. Terraform validate/plan (see above).
2. After `terraform apply` completes, check the VM IP output: `terraform output instance_ip`.
3. From an allowed IP (per `ssh_cidr` / `admin_cidr`), verify containers and service:

```bash
gcloud compute ssh <instance> --zone <zone> --project <project> --command "\
	docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' ; \
	systemctl status nyc_taxi_ingest.service --no-pager || true ; \
	journalctl -u nyc_taxi_ingest.service -n 200 --no-pager || true"
```

4. Connect to Postgres (pgAdmin or psql) and run the validation counts and analytical queries.

Packaging & archiving
---------------------
- `.env` is excluded from version control. Use `.env.example` as the template for users.
- Terraform state files and local data are excluded by `.gitignore`.

Contact / contributions
-----------------------
This project is intended for educational use. Development is ongoing. Pull requests and issues are welcome.
When contributing, avoid committing secrets and follow the project's security notes.

