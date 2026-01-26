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
	default     = "0.0.0.0/0"
}


