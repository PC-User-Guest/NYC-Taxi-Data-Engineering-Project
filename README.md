# NYC Taxi Data Engineering Project

Overview
--------
This repository implements a turnkey NYC Taxi data engineering pipeline that runs on a small GCP VM (Always Free eligible), using Dockerized PostgreSQL + pgAdmin for local analytics, and provisions a GCS bucket and BigQuery dataset via Terraform.

Architecture
------------
- GCP Compute Engine f1-micro instance that boots, installs Docker, and runs the project via `docker-compose`.
- Docker Compose runs PostgreSQL 16 and pgAdmin.
- Terraform provisions a GCS bucket and a BigQuery dataset.
- A systemd service runs `python/ingest_data.py` to load the Green taxi Parquet and zone CSV into Postgres.

Quick Setup
-----------
1. Install Terraform and configure `gcloud` with the desired project.
2. Edit `terraform/terraform.tfvars` and set `project = "your-gcp-project-id"`. Optionally set `repo_url` to a Git URL where this repository is hosted so the VM can clone it at boot.
3. Run:

```bash
terraform init
terraform apply -auto-approve
```

What the apply does
-------------------
- Creates a GCE f1-micro VM with a startup script that installs Docker, Docker Compose, Python, clones the repo (if `repo_url` provided), and starts the services.
- Creates a GCS bucket (`bucket_name`) and a BigQuery dataset (`bq_dataset`).

Accessing Services
------------------
- pgAdmin: http://<instance-ip>:8080 (credentials stored in `.env` as `PGADMIN_EMAIL` / `PGADMIN_PASSWORD`)
- Postgres: host `<instance-ip>`, port `15432`, database and user configured via `.env` (`POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`).

Running Locally (without Terraform)
----------------------------------
You can run the stack locally with Docker Compose:

```bash
cd docker
docker compose up -d
```

Then to run ingestion manually:

```bash
python3 python/ingest_data.py
```

Testing analytical queries
--------------------------
After ingestion, connect to Postgres and run queries to answer the analytical requirements. Example SQL:

1) Trips in Nov 2025 with trip_distance <= 1:

```sql
SELECT count(*) FROM nyc.taxi_trips
WHERE pickup_datetime >= '2025-11-01' AND pickup_datetime < '2025-12-01'
AND trip_distance <= 1;
```

2) Pickup day with the longest trip (trip_distance < 100):

```sql
SELECT date_trunc('day', pickup_datetime) as day,
	   max(trip_distance) as max_trip
FROM nyc.taxi_trips
WHERE trip_distance < 100
GROUP BY day
ORDER BY max_trip DESC
LIMIT 1;
```

3) Pickup zone with largest total_amount on Nov 18, 2025:

```sql
SELECT z.zone, SUM(t.total_amount) as total
FROM nyc.taxi_trips t
JOIN nyc.taxi_zones z ON z.location_id = t.pickup_location_id
WHERE t.pickup_datetime >= '2025-11-18' AND t.pickup_datetime < '2025-11-19'
GROUP BY z.zone
ORDER BY total DESC
LIMIT 1;
```

4) For pickups in "East Harlem North", which dropoff zone had largest total tip:

```sql
SELECT z2.zone, SUM(t.tip_amount) as total_tips
FROM nyc.taxi_trips t
JOIN nyc.taxi_zones z1 ON z1.location_id = t.pickup_location_id
JOIN nyc.taxi_zones z2 ON z2.location_id = t.dropoff_location_id
WHERE z1.zone = 'East Harlem North'
GROUP BY z2.zone
ORDER BY total_tips DESC
LIMIT 1;
```

Archiving
---------
- This repo is self-contained. To archive, create a tarball of the repository root.

Notes & Assumptions
-------------------
- The Terraform startup script can clone this repo if `repo_url` is provided. If you prefer to embed the repo in a bucket, upload a `repo.tar.gz` to the created GCS bucket with the same path.
- The ingestion script prefers local copies in `data/` and will download the required datasets when missing.

