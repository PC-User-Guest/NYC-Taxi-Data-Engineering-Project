import os
import sys
import time
import logging
from pathlib import Path
from typing import Optional

import requests
import pandas as pd
import pyarrow.dataset as ds
from tqdm import tqdm
from sqlalchemy import create_engine, text


LOGGER = logging.getLogger("nyc_taxi_ingest")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")


# Configuration (read from environment or .env). Do NOT hardcode secrets here.
DB_HOST = os.environ.get("PG_HOST", "localhost")
DB_PORT = int(os.environ.get("PG_PORT", 15432))
DB_NAME = os.environ.get("POSTGRES_DB")
DB_USER = os.environ.get("POSTGRES_USER")
DB_PASS = os.environ.get("POSTGRES_PASSWORD")

CHUNK_SIZE = int(os.environ.get("INGEST_CHUNK_SIZE", 10000))

if not DB_NAME or not DB_USER or not DB_PASS:
	LOGGER.error("POSTGRES_DB, POSTGRES_USER and POSTGRES_PASSWORD must be provided via environment (e.g. .env)")
	sys.exit(2)


BASE_DIR = Path(__file__).resolve().parents[1]
DATA_DIR = BASE_DIR / "data"
DATA_DIR.mkdir(parents=True, exist_ok=True)

# Dataset sources (stable public URLs)
GREEN_PARQUET_URL = os.environ.get(
	"GREEN_PARQUET_URL",
	"https://d37ci6vzurychx.cloudfront.net/trip-data/green_tripdata_2025-11.parquet",
)
ZONES_CSV_URL = os.environ.get(
	"ZONES_CSV_URL",
	"https://github.com/DataTalksClub/nyc-tlc-data/releases/download/misc/taxi_zone_lookup.csv",
)

GREEN_FILE = DATA_DIR / "green_tripdata_2025-11.parquet"
ZONES_FILE = DATA_DIR / "taxi_zone_lookup.csv"


def download_if_missing(url: str, path: Path) -> Path:
	"""Download remote `url` to `path` if not already present.

	The function avoids printing file contents or secrets; it only emits progress.
	"""
	if path.exists() and path.stat().st_size > 100:
		LOGGER.info("Found local file: %s", path)
		return path

	LOGGER.info("Downloading %s -> %s", url, path)
	with requests.get(url, stream=True, timeout=60) as r:
		r.raise_for_status()
		with open(path, "wb") as f:
			for chunk in r.iter_content(chunk_size=8192):
				if chunk:
					f.write(chunk)
	return path


def load_zones(engine) -> None:
	"""Load taxi zone lookup into `nyc.taxi_zones`.

	This operation is idempotent: we truncate and re-write the table so re-runs
	replace the previous content without duplication.
	"""
	LOGGER.info("Loading taxi zones from %s", ZONES_FILE)
	df = pd.read_csv(ZONES_FILE)
	df = df.rename(columns={
		"LocationID": "location_id",
		"Borough": "borough",
		"Zone": "zone",
		"service_zone": "service_zone",
	})
	df["location_id"] = df["location_id"].astype(int)

	with engine.begin() as conn:
		conn.execute(text("TRUNCATE TABLE nyc.taxi_zones"))
		df.to_sql("taxi_zones", conn, schema="nyc", if_exists="append", index=False)
	LOGGER.info("Loaded %d zone rows", len(df))


def _map_columns(batch_df: pd.DataFrame) -> pd.DataFrame:
	"""Normalize column names from source to the destination schema.

	This helper maps multiple possible source column names to the canonical
	destination columns used by the Postgres schema.
	"""
	# Lowercase mapping for robust matching
	src_cols = {c.lower(): c for c in batch_df.columns}

	def pick(*opts):
		for opt in opts:
			key = opt.lower()
			if key in src_cols:
				return batch_df[src_cols[key]]
		return None

	out = pd.DataFrame()
	out["vendor_id"] = pick("vendorid", "vendor_id")
	out["pickup_datetime"] = pd.to_datetime(pick("lpep_pickup_datetime", "pickup_datetime", "tpep_pickup_datetime"), errors="coerce")
	out["dropoff_datetime"] = pd.to_datetime(pick("lpep_dropoff_datetime", "dropoff_datetime", "tpep_dropoff_datetime"), errors="coerce")
	out["store_and_fwd_flag"] = pick("store_and_fwd_flag", "store_and_fwd")
	out["rate_code_id"] = pick("ratecodeid", "rate_code_id", "ratecode")
	out["pickup_location_id"] = pick("pulocationid", "pu_location_id", "pickup_location_id")
	out["dropoff_location_id"] = pick("dolocationid", "do_location_id", "dropoff_location_id")
	out["passenger_count"] = pick("passengercount", "passenger_count")
	out["trip_distance"] = pick("trip_distance")
	out["fare_amount"] = pick("fare_amount")
	out["extra"] = pick("extra")
	out["mta_tax"] = pick("mta_tax", "mtatax")
	out["tip_amount"] = pick("tip_amount")
	out["tolls_amount"] = pick("tolls_amount")
	out["improvement_surcharge"] = pick("improvement_surcharge")
	out["total_amount"] = pick("total_amount")
	out["payment_type"] = pick("payment_type")
	out["trip_type"] = pick("trip_type")
	out["congestion_surcharge"] = pick("congestion_surcharge")

	# keep only rows with a pickup datetime
	out = out[out["pickup_datetime"].notna()]
	return out


def load_trips_chunked(engine, parquet_path: Path, chunk_size: int = CHUNK_SIZE) -> None:
	"""Stream-parquet ingestion using pyarrow.dataset to limit memory usage.

	The function deletes the target month window before inserting to ensure
	idempotency when re-running the pipeline for the same month.
	"""
	LOGGER.info("Beginning chunked trip ingestion from %s (chunk_size=%d)", parquet_path, chunk_size)

	# Define the Nov 2025 window we consider canonical for this dataset.
	start = pd.Timestamp("2025-11-01")
	end = pd.Timestamp("2025-12-01")

	# Delete overlapping rows first (idempotency)
	with engine.begin() as conn:
		conn.execute(text("DELETE FROM nyc.taxi_trips WHERE pickup_datetime >= :start AND pickup_datetime < :end"), {"start": start, "end": end})

	dataset = ds.dataset(str(parquet_path), format="parquet")
	# Use the pyarrow scanner to iterate record batches
	scanner = dataset.scan()
	batches = scanner.to_batches(batch_size=chunk_size)

	total_rows = 0
	for batch in tqdm(batches, desc="Ingesting parquet batches"):
		batch_df = batch.to_pandas()
		mapped = _map_columns(batch_df)
		if len(mapped) == 0:
			continue
		with engine.begin() as conn:
			mapped.to_sql("taxi_trips", conn, schema="nyc", if_exists="append", index=False)
		total_rows += len(mapped)

	LOGGER.info("Inserted %d trip rows", total_rows)


def main() -> None:
	"""Main entrypoint for ingestion.

	Typical usage: this script is executed by a systemd service on the VM, or
	run manually for development. It reads DB credentials from the environment
	(recommended via a secure `.env` file) and streams the Parquet dataset
	into Postgres in chunks to avoid high memory usage.
	"""
	LOGGER.info("Starting ingestion")

	# ensure files
	try:
		download_if_missing(GREEN_PARQUET_URL, GREEN_FILE)
	except Exception as e:
		LOGGER.warning("Failed to download parquet: %s", e)
	try:
		download_if_missing(ZONES_CSV_URL, ZONES_FILE)
	except Exception as e:
		LOGGER.warning("Failed to download zones csv: %s", e)

	# Connect to DB using SQLAlchemy. Credentials come from environment variables.
	url = f"postgresql+psycopg2://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
	engine = create_engine(url, pool_pre_ping=True)

	# retry until DB is ready
	for attempt in range(30):
		try:
			with engine.connect() as conn:
				conn.execute(text("SELECT 1"))
			break
		except Exception as e:
			LOGGER.info("DB not ready, retrying: %s", str(e))
			time.sleep(3)
	else:
		LOGGER.error("Failed to connect to DB after retries")
		sys.exit(1)

	# Load zones then trips (chunked)
	load_zones(engine)
	load_trips_chunked(engine, GREEN_FILE, chunk_size=CHUNK_SIZE)

	LOGGER.info("Ingestion complete")


if __name__ == "__main__":
	main()

