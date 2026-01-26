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

resource "google_compute_firewall" "ssh" {
	name    = "allow-ssh-nyc-taxi"
	network = google_compute_network.default.name

	allow {
		protocol = "tcp"
		ports    = ["22"]
	}

	source_ranges = [var.ssh_cidr]
}

resource "google_compute_firewall" "http" {
	name    = "allow-pgadmin-nyc-taxi"
	network = google_compute_network.default.name

	allow {
		protocol = "tcp"
		ports    = ["8080"]
	}

	source_ranges = ["0.0.0.0/0"]
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

		access_config {}
	}

	metadata_startup_script = <<-EOT
		#!/bin/bash
		set -eux
		apt-get update
		apt-get install -y git curl ca-certificates gnupg lsb-release python3 python3-venv python3-pip
		curl -fsSL https://get.docker.com | sh
		pip3 install --upgrade pip
		pip3 install docker-compose

		mkdir -p /opt/nyc_taxi
		chown -R $USER:$USER /opt/nyc_taxi || true

		if [ -n "${var.repo_url}" ]; then
			git clone --branch ${var.repo_branch} ${var.repo_url} /opt/nyc_taxi || (cd /opt/nyc_taxi && git pull || true)
		fi

		# try to ensure .env is present in /opt/nyc_taxi
		if [ -f /opt/nyc_taxi/.env ]; then
			echo ".env already present in repo"
		else
			if command -v gsutil >/dev/null 2>&1; then
				gsutil cp gs://${var.bucket_name}/.env /opt/nyc_taxi/.env || true
			fi
		fi
		chown -R $USER:$USER /opt/nyc_taxi || true

		# If repo not present but a bucket exists, try to fetch a repo archive
		if [ ! -f /opt/nyc_taxi/docker/docker-compose.yaml ] && command -v gsutil >/dev/null 2>&1; then
			gsutil cp gs://${var.bucket_name}/repo.tar.gz /tmp/repo.tar.gz || true
			if [ -f /tmp/repo.tar.gz ]; then
				tar -xzf /tmp/repo.tar.gz -C /opt/nyc_taxi --strip-components=1 || true
			fi
		fi

		# start docker-compose if present
		if [ -f /opt/nyc_taxi/docker/docker-compose.yaml ]; then
			cd /opt/nyc_taxi/docker
			docker compose up -d || docker-compose up -d || true
		fi

		# Make systemd service for ingestion. Load environment from /opt/nyc_taxi/.env if present.
		cat > /etc/systemd/system/nyc_taxi_ingest.service <<'SERVICE'
	[Unit]
	Description=NYC Taxi ingestion service
	After=docker.service

	[Service]
	Type=oneshot
	EnvironmentFile=/opt/nyc_taxi/.env
	ExecStart=/usr/bin/python3 /opt/nyc_taxi/python/ingest_data.py
	RemainAfterExit=yes

	[Install]
	WantedBy=multi-user.target
	SERVICE
		# reload and enable the service
		systemctl daemon-reload || true
		systemctl enable nyc_taxi_ingest.service || true
		systemctl start nyc_taxi_ingest.service || true
	EOT

	tags = ["nyc-taxi-instance"]
}

resource "google_storage_bucket" "data" {
	name     = length(var.bucket_name) > 0 ? var.bucket_name : "nyc-taxi-data-bucket-${random_id.bucket_suffix.hex}"
	location = var.region
	force_destroy = true
}

resource "google_bigquery_dataset" "nyc_taxi" {
	dataset_id = var.bq_dataset
	location   = upper(var.region)
}

resource "random_id" "bucket_suffix" {
	byte_length = 2
}

