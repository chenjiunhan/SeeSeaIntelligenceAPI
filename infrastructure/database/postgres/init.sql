-- PostgreSQL + TimescaleDB Initialization Script
-- Creates tables for vessel arrival data

-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Create chokepoints metadata table
CREATE TABLE IF NOT EXISTS chokepoints (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL,
    display_name VARCHAR(100),
    latitude DECIMAL(10, 7),
    longitude DECIMAL(10, 7),
    description TEXT,
    importance_level INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert chokepoint data
INSERT INTO chokepoints (name, display_name, latitude, longitude, importance_level) VALUES
('suez-canal', 'Suez Canal', 30.5, 32.3, 5),
('strait-of-hormuz', 'Strait of Hormuz', 26.5, 56.3, 5),
('strait-of-malacca', 'Strait of Malacca', 2.5, 100.4, 5),
('panama-canal', 'Panama Canal', 9.0, -79.9, 4),
('bosporus-strait', 'Bosporus Strait', 41.1, 29.0, 3),
('bab-el-mandeb', 'Bab el-Mandeb', 12.6, 43.3, 4)
ON CONFLICT (name) DO NOTHING;

-- Create vessel arrivals table
CREATE TABLE IF NOT EXISTS vessel_arrivals (
    id BIGSERIAL PRIMARY KEY,
    date DATE NOT NULL,
    chokepoint VARCHAR(50) NOT NULL,
    vessel_count INTEGER NOT NULL,
    container INTEGER DEFAULT 0,
    dry_bulk INTEGER DEFAULT 0,
    general_cargo INTEGER DEFAULT 0,
    roro INTEGER DEFAULT 0,
    tanker INTEGER DEFAULT 0,
    collected_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_date_chokepoint UNIQUE(date, chokepoint)
);

-- Convert to TimescaleDB hypertable
SELECT create_hypertable(
    'vessel_arrivals',
    'date',
    chunk_time_interval => INTERVAL '1 month',
    if_not_exists => TRUE
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_chokepoint_date ON vessel_arrivals(chokepoint, date DESC);
CREATE INDEX IF NOT EXISTS idx_date ON vessel_arrivals(date DESC);
CREATE INDEX IF NOT EXISTS idx_collected_at ON vessel_arrivals(collected_at DESC);

-- Create materialized view for daily summary
CREATE MATERIALIZED VIEW IF NOT EXISTS daily_summary AS
SELECT
    date,
    chokepoint,
    vessel_count,
    (container + dry_bulk + tanker) AS total_cargo_vessels,
    ROUND(
        vessel_count::numeric /
        NULLIF((container + dry_bulk + general_cargo + roro + tanker), 0) * 100,
        2
    ) as data_completeness
FROM vessel_arrivals;

CREATE INDEX IF NOT EXISTS idx_daily_summary ON daily_summary(chokepoint, date DESC);

-- Function to refresh materialized view
CREATE OR REPLACE FUNCTION refresh_daily_summary()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY daily_summary;
END;
$$ LANGUAGE plpgsql;

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO admin;

-- Print success message
DO $$
BEGIN
    RAISE NOTICE 'PostgreSQL database initialized successfully!';
END $$;
