variable "project" {
	description = "GCP project ID"
	type        = string
}

variable "region" {
	description = "GCP region"
	type        = string
	default     = "us-central1"
}

variable "zone" {
	description = "GCP zone"
	type        = string
	default     = "us-central1-a"
}

variable "machine_type" {
	description = "GCE machine type (Always Free eligible)"
	type        = string
	default     = "f1-micro"
}

variable "instance_name" {
	description = "Compute instance name"
	type        = string
	default     = "nyc-taxi-vm"
}

variable "bucket_name" {
	description = "GCS bucket name to create (leave empty to auto-generate)"
	type        = string
	default     = ""
}

variable "bq_dataset" {
	description = "BigQuery dataset name"
	type        = string
	default     = "nyc_taxi_dataset"
}

variable "repo_url" {
	description = "Optional git repo URL for the project. If set, startup script will clone this repo into /opt/nyc_taxi"
	type        = string
	default     = ""
}

variable "repo_branch" {
	description = "Optional git branch to clone"
	type        = string
	default     = "main"
}

variable "ssh_cidr" {
	description = "CIDR allowed for SSH access"
	type        = string
	# Require operator to set a narrow CIDR (no open default)
	default     = ""
	validation {
		condition     = length(var.ssh_cidr) > 0
		error_message = "ssh_cidr must be set to a single trusted CIDR (do not use 0.0.0.0/0)"
	}
}

variable "admin_cidr" {
	description = "CIDR allowed for admin HTTP access (pgAdmin). Set to the same as ssh_cidr to restrict access."
	type        = string
	default     = ""
	validation {
		condition     = length(var.admin_cidr) > 0
		error_message = "admin_cidr must be set to a single trusted CIDR for pgAdmin access"
	}
}


