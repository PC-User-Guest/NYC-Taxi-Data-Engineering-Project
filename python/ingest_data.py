import os
import sys
import time
import requests
import pandas as pd
from sqlalchemy import create_engine, text

# Configuration (read secrets from environment/.env)
DB_HOST = os.environ.get("PG_HOST", "localhost")
DB_PORT = int(os.environ.get("PG_PORT", 15432))
DB_NAME = os.environ.get("POSTGRES_DB")
DB_USER = os.environ.get("POSTGRES_USER")
DB_PASS = os.environ.get("POSTGRES_PASSWORD")

if not DB_NAME or not DB_USER or not DB_PASS:
	print("ERROR: POSTGRES_DB, POSTGRES_USER and POSTGRES_PASSWORD must be provided via environment (e.g. .env)")
	sys.exit(2)

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DATA_DIR = os.path.join(BASE_DIR, "data")
os.makedirs(DATA_DIR, exist_ok=True)

GREEN_PARQUET_URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/green_tripdata_2025-11.parquet"
ZONES_CSV_URL = "https://github.com/DataTalksClub/nyc-tlc-data/releases/download/misc/taxi_zone_lookup.csv"

GREEN_FILE = os.path.join(DATA_DIR, "green_tripdata_2025-11.parquet")
ZONES_FILE = os.path.join(DATA_DIR, "taxi_zone_lookup.csv")


def download_if_missing(url, path):
	if os.path.exists(path) and os.path.getsize(path) > 100:
		print(f"Found local file: {path}")
		return path
	print(f"Downloading {url} -> {path}")
	with requests.get(url, stream=True, timeout=60) as r:
		r.raise_for_status()
		with open(path, "wb") as f:
			for chunk in r.iter_content(chunk_size=8192):
				if chunk:
					f.write(chunk)
	return path


def load_zones(engine):
	df = pd.read_csv(ZONES_FILE)
	df = df.rename(columns={
		"LocationID": "location_id",
		"Borough": "borough",
		"Zone": "zone",
		"service_zone": "service_zone"
	})
	df['location_id'] = df['location_id'].astype(int)

	with engine.begin() as conn:
		# replace existing zones (idempotent)
		conn.execute(text("TRUNCATE TABLE nyc.taxi_zones"))
		df.to_sql('taxi_zones', conn, schema='nyc', if_exists='append', index=False)


def load_trips(engine):
	# read parquet
		df_raw = pd.read_parquet(GREEN_FILE)

		# Build a sanitized dataframe matching DB column names
		def pick(col_options):
			for opt in col_options:
				for c in df_raw.columns:
					if c.lower() == opt:
						return df_raw[c]
			return None

		df = pd.DataFrame()
		df['vendor_id'] = pick(['vendorid', 'vendor_id'])
		df['pickup_datetime'] = pd.to_datetime(pick(['lpep_pickup_datetime', 'pickup_datetime', 'tpep_pickup_datetime']), errors='coerce')
		df['dropoff_datetime'] = pd.to_datetime(pick(['lpep_dropoff_datetime', 'dropoff_datetime', 'tpep_dropoff_datetime']), errors='coerce')
		df['store_and_fwd_flag'] = pick(['store_and_fwd_flag', 'store_and_fwd'])
		df['rate_code_id'] = pick(['ratecodeid', 'rate_code_id', 'ratecode'])
		df['pickup_location_id'] = pick(['pulocationid', 'pu_location_id', 'pickup_location_id'])
		df['dropoff_location_id'] = pick(['dolocationid', 'do_location_id', 'dropoff_location_id'])
		df['passenger_count'] = pick(['passengercount', 'passenger_count'])
		df['trip_distance'] = pick(['trip_distance'])
		df['fare_amount'] = pick(['fare_amount'])
		df['extra'] = pick(['extra'])
		df['mta_tax'] = pick(['mta_tax', 'mtatax'])
		df['tip_amount'] = pick(['tip_amount'])
		df['tolls_amount'] = pick(['tolls_amount'])
		df['improvement_surcharge'] = pick(['improvement_surcharge'])
		df['total_amount'] = pick(['total_amount'])
		df['payment_type'] = pick(['payment_type'])
		df['trip_type'] = pick(['trip_type'])
		df['congestion_surcharge'] = pick(['congestion_surcharge'])

		# Filter out rows without pickup datetime
		df = df[df['pickup_datetime'].notna()]

		# Delete overlapping Nov 2025 rows then insert
		start = pd.Timestamp('2025-11-01')
		end = pd.Timestamp('2025-12-01')

		with engine.begin() as conn:
			conn.execute(text("DELETE FROM nyc.taxi_trips WHERE pickup_datetime >= :start AND pickup_datetime < :end"), {"start": start, "end": end})
			df.to_sql('taxi_trips', conn, schema='nyc', if_exists='append', index=False)


def main():
	print('Starting ingestion')
	# ensure files
	try:
		download_if_missing(GREEN_PARQUET_URL, GREEN_FILE)
	except Exception as e:
		print('Warning: failed to download parquet:', e)
	try:
		download_if_missing(ZONES_CSV_URL, ZONES_FILE)
	except Exception as e:
		print('Warning: failed to download zones csv:', e)

	# Connect to DB
	url = f"postgresql+psycopg2://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
	engine = create_engine(url, pool_pre_ping=True)

	# retry until DB is ready
	for attempt in range(30):
		try:
			with engine.connect() as conn:
				conn.execute(text('SELECT 1'))
			break
		except Exception as e:
			print('DB not ready, retrying...', str(e))
			time.sleep(3)
	else:
		print('Failed to connect to DB after retries')
		sys.exit(1)

	# Load zones then trips
	load_zones(engine)
	load_trips(engine)

	print('Ingestion complete')


if __name__ == '__main__':
	main()

