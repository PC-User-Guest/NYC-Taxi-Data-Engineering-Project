-- idempotent user and database creation
DO
$$
BEGIN
	IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ny_taxi') THEN
		PERFORM dblink_exec('host=localhost user=postgres password=postgres','CREATE DATABASE ny_taxi');
	END IF;
EXCEPTION WHEN undefined_function THEN
	-- dblink may not be available during init; fall back to simple CREATE DATABASE if possible
	BEGIN
	  IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ny_taxi') THEN
		 CREATE DATABASE ny_taxi;
	  END IF;
	EXCEPTION WHEN others THEN
	  -- ignore during docker-entrypoint initialization where CREATE DATABASE may already run
	  NULL;
	END;
END
$$;

DO
$$
BEGIN
	IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'nyc_taxi_user') THEN
		CREATE ROLE nyc_taxi_user WITH LOGIN;
	END IF;
END
$$;

-- grant privileges on database if it exists
DO
$$
BEGIN
	IF EXISTS (SELECT FROM pg_database WHERE datname = 'ny_taxi') THEN
		EXECUTE format('GRANT CONNECT ON DATABASE %I TO %I', 'ny_taxi', 'nyc_taxi_user');
	END IF;
END
$$;

