-- Initialize schema and tables for NYC taxi analytics
-- Initialize schema and tables for NYC taxi analytics

-- This file creates a small, analytics-oriented schema suitable for
-- classroom examples and small-scale experimentation. Naming uses
-- snake_case and indexes are intentionally lightweight to support
-- the example analytical queries.

CREATE SCHEMA IF NOT EXISTS nyc;

-- Taxi zones lookup: stable, small reference table used for joins.
CREATE TABLE IF NOT EXISTS nyc.taxi_zones (
	location_id INTEGER PRIMARY KEY,
	borough TEXT,
	zone TEXT,
	service_zone TEXT
);

-- Taxi trips: a pared-down subset of Green Taxi columns focused on
-- analytics. We use a BIGSERIAL `trip_id` for a stable primary key.
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

-- Indexes to accelerate the example queries (date range and location joins).
CREATE INDEX IF NOT EXISTS idx_taxi_trips_pickup_dt ON nyc.taxi_trips (pickup_datetime);
CREATE INDEX IF NOT EXISTS idx_taxi_trips_pickup_loc ON nyc.taxi_trips (pickup_location_id);
CREATE INDEX IF NOT EXISTS idx_taxi_trips_dropoff_loc ON nyc.taxi_trips (dropoff_location_id);

