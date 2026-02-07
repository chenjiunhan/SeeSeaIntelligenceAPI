"""
PostgreSQL to ClickHouse Sync
Syncs data from PostgreSQL to ClickHouse for analytics
"""
import os
import psycopg2
from clickhouse_driver import Client
from dotenv import load_dotenv
from datetime import datetime, timedelta

load_dotenv()

def sync_to_clickhouse():
    """Sync PostgreSQL data to ClickHouse"""

    # Connect to PostgreSQL
    pg_conn = psycopg2.connect(os.getenv('DATABASE_URL'))
    pg_cursor = pg_conn.cursor()

    # Connect to ClickHouse
    ch_client = Client.from_url(os.getenv('CLICKHOUSE_URL'))

    # Get yesterday's data
    yesterday = (datetime.now() - timedelta(days=1)).date()

    print(f"Syncing data for {yesterday}")

    # Fetch data from PostgreSQL
    pg_cursor.execute("""
        SELECT date, chokepoint, vessel_count, container, dry_bulk,
               general_cargo, roro, tanker, collected_at
        FROM vessel_arrivals
        WHERE date = %s
    """, (yesterday,))

    rows = pg_cursor.fetchall()

    if not rows:
        print(f"No data found for {yesterday}")
        return

    # Insert into ClickHouse
    ch_client.execute("""
        INSERT INTO vessel_arrivals_analytics
        (date, chokepoint, vessel_count, container, dry_bulk,
         general_cargo, roro, tanker, collected_at)
        VALUES
    """, rows)

    print(f"✅ Synced {len(rows)} records to ClickHouse")

    pg_cursor.close()
    pg_conn.close()

if __name__ == "__main__":
    sync_to_clickhouse()
