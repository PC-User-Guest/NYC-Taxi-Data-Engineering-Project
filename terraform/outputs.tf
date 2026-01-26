output "instance_ip" {
	description = "External IP of the VM"
	value       = google_compute_instance.vm.network_interface[0].access_config[0].nat_ip
}

output "bucket_name" {
	value = google_storage_bucket.data.name
}

output "bq_dataset" {
	value = google_bigquery_dataset.nyc_taxi.dataset_id
}

