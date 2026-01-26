-- Initialize schema and tables for NYC taxi analytics

CREATE SCHEMA IF NOT EXISTS nyc;

-- Taxi zones lookup
CREATE TABLE IF NOT EXISTS nyc.taxi_zones (
	location_id INTEGER PRIMARY KEY,
	borough TEXT,
	zone TEXT,
	service_zone TEXT
);

-- Taxi trips (Green Taxi partial schema tuned for analytics)
CREATE TABLE IF NOT EXISTS nyc.taxi_trips (
	trip_id BIGSERIAL PRIMARY KEY,
	vendor_id INTEGER,
	pickup_datetime TIMESTAMP WITHOUT TIME ZONE,
	dropoff_datetime TIMESTAMP WITHOUT TIME ZONE,
	store_and_fwd_flag TEXT,
	rate_code_id INTEGER,
	pickup_location_id INTEGER,
	dropoff_location_id INTEGER,
	passenger_count INTEGER,
	trip_distance DOUBLE PRECISION,
	fare_amount NUMERIC,
	extra NUMERIC,
	mta_tax NUMERIC,
	tip_amount NUMERIC,
	tolls_amount NUMERIC,
	improvement_surcharge NUMERIC,
	total_amount NUMERIC,
	payment_type INTEGER,
	trip_type INTEGER,
	congestion_surcharge NUMERIC
);

-- Helpful indexes
CREATE INDEX IF NOT EXISTS idx_taxi_trips_pickup_dt ON nyc.taxi_trips (pickup_datetime);
CREATE INDEX IF NOT EXISTS idx_taxi_trips_pickup_loc ON nyc.taxi_trips (pickup_location_id);
CREATE INDEX IF NOT EXISTS idx_taxi_trips_dropoff_loc ON nyc.taxi_trips (dropoff_location_id);

