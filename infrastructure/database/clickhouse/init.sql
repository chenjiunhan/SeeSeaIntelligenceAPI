-- ClickHouse Initialization Script
-- Creates analytics tables with columnar storage

-- Create database
CREATE DATABASE IF NOT EXISTS seesea_analytics;

-- Use the analytics database
USE seesea_analytics;

-- Create main analytics table (columnar storage)
CREATE TABLE IF NOT EXISTS vessel_arrivals_analytics (
    date Date,
    chokepoint LowCardinality(String),
    vessel_count UInt32,
    container UInt16,
    dry_bulk UInt16,
    general_cargo UInt16,
    roro UInt16,
    tanker UInt16,
    collected_at DateTime
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(date)
ORDER BY (chokepoint, date)
SETTINGS index_granularity = 8192;

-- Create monthly summary materialized view
CREATE MATERIALIZED VIEW IF NOT EXISTS monthly_summary_mv
ENGINE = SummingMergeTree()
PARTITION BY toYear(month)
ORDER BY (chokepoint, month)
AS SELECT
    toStartOfMonth(date) as month,
    chokepoint,
    sum(vessel_count) as total_vessels,
    avg(vessel_count) as avg_vessels,
    max(vessel_count) as peak_vessels,
    min(vessel_count) as min_vessels,
    sum(container) as total_containers,
    sum(tanker) as total_tankers
FROM vessel_arrivals_analytics
GROUP BY month, chokepoint;

-- Create weekly summary materialized view
CREATE MATERIALIZED VIEW IF NOT EXISTS weekly_summary_mv
ENGINE = SummingMergeTree()
ORDER BY (chokepoint, week)
AS SELECT
    toStartOfWeek(date) as week,
    chokepoint,
    sum(vessel_count) as total_vessels,
    avg(vessel_count) as avg_vessels,
    sumIf(container, container > 0) as total_containers,
    sumIf(tanker, tanker > 0) as total_tankers,
    sumIf(dry_bulk, dry_bulk > 0) as total_dry_bulk
FROM vessel_arrivals_analytics
GROUP BY week, chokepoint;

-- Create a sample query function for testing
SELECT 'ClickHouse analytics database initialized successfully!' as status;
