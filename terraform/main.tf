terraform {
	required_providers {
		google = {
			source  = "hashicorp/google"
			version = "~> 4.0"
		}
		random = {
			source  = "hashicorp/random"
			version = "~> 3.0"
		}
	}
}

provider "google" {
	project = var.project
	region  = var.region
	zone    = var.zone
}

resource "google_compute_network" "default" {
	name = "nyc-taxi-network"
}

resource "google_project_service" "compute" {
	project = var.project
	service = "compute.googleapis.com"
}

resource "google_project_service" "storage" {
	project = var.project
	service = "storage.googleapis.com"
}

resource "google_project_service" "bigquery" {
	project = var.project
	service = "bigquery.googleapis.com"
}


resource "google_compute_firewall" "ssh" {
	name    = "allow-ssh-nyc-taxi"
	network = google_compute_network.default.name

	allow {
		protocol = "tcp"
		ports    = ["22"]
	}

	# Restrict SSH to operator-provided CIDR (must be set via variable)
	source_ranges = [var.ssh_cidr]
	target_tags   = ["nyc-taxi-instance"]
	priority      = 100
}

resource "google_compute_firewall" "pgadmin_http" {
	name    = "allow-pgadmin-nyc-taxi"
	network = google_compute_network.default.name

	allow {
		protocol = "tcp"
		ports    = ["8080"]
	}

	# Restrict admin UI (pgAdmin) to operator-provided admin CIDR
	source_ranges = [var.admin_cidr]
	target_tags   = ["nyc-taxi-instance"]
	priority      = 110
}

# Explicit deny for PostgreSQL external exposure. This prevents accidental exposure
# even if Docker publishes the DB port on the VM's network interface.
resource "google_compute_firewall" "deny_postgres_external" {
	name    = "deny-postgres-external-nyc-taxi"
	network = google_compute_network.default.name

	direction = "INGRESS"
	priority  = 1000

	deny {
		protocol = "tcp"
		ports    = ["15432"]
	}

	source_ranges = ["0.0.0.0/0"]
	target_tags   = ["nyc-taxi-instance"]
}

resource "google_compute_instance" "vm" {
	name         = var.instance_name
	machine_type = var.machine_type
	zone         = var.zone

	boot_disk {
		initialize_params {
			image = "debian-cloud/debian-11"
			size  = 30
			type  = "pd-standard"
		}
	}

	network_interface {
		network = google_compute_network.default.id

		# Keep an external IP for management if required by operator
		access_config {}
	}

	metadata_startup_script = <<-EOT
		#!/bin/bash
		set -euo pipefail
		apt-get update
		apt-get install -y git curl ca-certificates gnupg lsb-release python3 python3-venv python3-pip
		curl -fsSL https://get.docker.com | sh
		pip3 install --upgrade pip
		pip3 install docker-compose || true

		mkdir -p /opt/nyc_taxi

		if [ -n "${var.repo_url}" ]; then
			git clone --branch ${var.repo_branch} ${var.repo_url} /opt/nyc_taxi || (cd /opt/nyc_taxi && git pull || true)
		fi

		# Fetch .env from GCS bucket if present. Do NOT echo or log its contents.
		if command -v gsutil >/dev/null 2>&1; then
			if gsutil -q stat gs://${var.bucket_name}/.env; then
				gsutil cp gs://${var.bucket_name}/.env /opt/nyc_taxi/.env || true
				chown root:root /opt/nyc_taxi/.env || true
				chmod 600 /opt/nyc_taxi/.env || true
			fi
		fi

		# If repo archive is present in bucket, extract it.
		if command -v gsutil >/dev/null 2>&1; then
			if gsutil -q stat gs://${var.bucket_name}/repo.tar.gz; then
				gsutil cp gs://${var.bucket_name}/repo.tar.gz /tmp/repo.tar.gz || true
				if [ -f /tmp/repo.tar.gz ]; then
					tar -xzf /tmp/repo.tar.gz -C /opt/nyc_taxi --strip-components=1 || true
				fi
			fi
		fi

		# Start docker compose if present. Avoid printing environment variables.
		if [ -f /opt/nyc_taxi/docker/docker-compose.yaml ]; then
			cd /opt/nyc_taxi/docker
			docker compose up -d || docker-compose up -d || true
		fi

		# Create systemd unit for ingestion that reads /opt/nyc_taxi/.env (600 permissions).
		cat > /etc/systemd/system/nyc_taxi_ingest.service << 'SERVICE'
[Unit]
Description=NYC Taxi ingestion service
After=docker.service

[Service]
Type=simple
EnvironmentFile=/opt/nyc_taxi/.env
ExecStart=/usr/bin/python3 /opt/nyc_taxi/python/ingest_data.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
SERVICE
		systemctl daemon-reload || true
		systemctl enable nyc_taxi_ingest.service || true
		systemctl start nyc_taxi_ingest.service || true
	EOT

	tags = ["nyc-taxi-instance"]

	# Disallow IP forwarding on the VM to avoid misuse as a router
	can_ip_forward = false

	# Enable OS Login and Shielded VM features for improved instance hardening.
	metadata = {
		enable-oslogin = "TRUE"
	}

	shielded_instance_config {
		enable_secure_boot          = true
		enable_vtpm                = true
		enable_integrity_monitoring = true
	}

	service_account {
	  email  = google_service_account.vm_sa.email
	  scopes = [
	    "https://www.googleapis.com/auth/devstorage.read_write",
	    "https://www.googleapis.com/auth/bigquery"
	  ]
	}
}

resource "google_storage_bucket" "data" {
	name     = length(var.bucket_name) > 0 ? var.bucket_name : "nyc-taxi-data-bucket-${random_id.bucket_suffix.hex}"
	location = var.region
	force_destroy = true
	# Enforce uniform bucket-level access to avoid ACL-based public exposure.
	uniform_bucket_level_access = true
	versioning {
		enabled = true
	}
}

resource "google_bigquery_dataset" "nyc_taxi" {
	dataset_id = var.bq_dataset
	location   = upper(var.region)
	# Keep dataset access explicit; do not make it public. Access will be granted resource-scoped.
}

resource "random_id" "bucket_suffix" {
	byte_length = 2
}

# Dedicated service account for the VM (least privilege). IAM bindings below grant
# only the required roles on the specific resources (bucket and dataset).
resource "google_service_account" "vm_sa" {
	account_id   = "nyc-taxi-vm-sa"
	display_name = "NYC Taxi VM service account (least privilege)"
}

# Grant the service account bucket-scoped objectAdmin (resource-level binding).
resource "google_storage_bucket_iam_member" "vm_sa_bucket_access" {
	bucket = google_storage_bucket.data.name
	role   = "roles/storage.objectAdmin"
	member = "serviceAccount:${google_service_account.vm_sa.email}"
}

# Grant the service account dataset-scoped BigQuery dataEditor role.
resource "google_bigquery_dataset_iam_member" "vm_sa_bq_access" {
	dataset_id = google_bigquery_dataset.nyc_taxi.dataset_id
	role       = "roles/bigquery.dataEditor"
	member     = "serviceAccount:${google_service_account.vm_sa.email}"
}

