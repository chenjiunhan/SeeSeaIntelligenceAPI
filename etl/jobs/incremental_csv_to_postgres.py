"""
Incremental CSV to PostgreSQL ETL Job
Only processes new/updated records based on collected_at timestamp
"""
import os
from pathlib import Path
from datetime import datetime, timedelta
import pytz

import pandas as pd
import psycopg2
from psycopg2.extras import execute_batch
from dotenv import load_dotenv

load_dotenv()

def get_last_sync_time(cursor, chokepoint):
    """Get the last sync timestamp for a chokepoint"""
    cursor.execute("""
        SELECT MAX(collected_at)
        FROM vessel_arrivals
        WHERE chokepoint = %s
    """, (chokepoint,))

    result = cursor.fetchone()[0]
    if result is None:
        # If no data exists, sync all data - return UTC-aware datetime
        return datetime(2000, 1, 1, tzinfo=pytz.UTC)
    return result


def load_incremental_csv_to_postgres():
    """Load only new/updated CSV data to PostgreSQL"""

    # Database connection
    conn = psycopg2.connect(os.getenv('DATABASE_URL'))
    cursor = conn.cursor()

    # Find all CSV files from SeeSeaIntelligence repo
    # Try Docker mount path first, then fall back to local development path
    docker_path = Path('/data/processed/logistics/chokepoints')
    local_path = Path(__file__).parent.parent.parent.parent / 'SeeSeaIntelligence' / 'processed' / 'logistics' / 'chokepoints'

    if docker_path.exists():
        base_path = docker_path
        print(f"[{datetime.now()}] Using Docker mount path: {base_path}")
    elif local_path.exists():
        base_path = local_path
        print(f"[{datetime.now()}] Using local development path: {base_path}")
    else:
        raise FileNotFoundError(f"CSV directory not found. Tried: {docker_path} and {local_path}")

    csv_files = list(base_path.glob('*/vessel_arrivals/vessel_arrivals.csv'))

    print(f"[{datetime.now()}] Found {len(csv_files)} CSV files")

    total_new_records = 0
    total_updated_records = 0

    for csv_file in csv_files:
        try:
            # Read CSV
            df = pd.read_csv(csv_file)

            if df.empty:
                continue

            # Get chokepoint name from first row
            chokepoint = df.iloc[0]['chokepoint']

            # Get last sync time for this chokepoint
            last_sync = get_last_sync_time(cursor, chokepoint)

            # Convert collected_at to datetime for filtering
            df['collected_at_dt'] = pd.to_datetime(df['collected_at'])

            # Filter only new/updated records
            new_df = df[df['collected_at_dt'] > last_sync]

            if new_df.empty:
                print(f"  ⏭️  {chokepoint}: No new data since {last_sync}")
                continue

            print(f"  📥 {chokepoint}: Processing {len(new_df)} new/updated records")

            # Prepare batch data
            records = []
            for _, row in new_df.iterrows():
                records.append((
                    row['date'],
                    row['chokepoint'],
                    int(row['vessel_count']),
                    int(row['container']),
                    int(row['dry_bulk']),
                    int(row['general_cargo']),
                    int(row['roro']),
                    int(row['tanker']),
                    row['collected_at']
                ))

            # Batch insert/update
            execute_batch(cursor, """
                INSERT INTO vessel_arrivals
                (date, chokepoint, vessel_count, container, dry_bulk,
                 general_cargo, roro, tanker, collected_at)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (date, chokepoint) DO UPDATE SET
                    vessel_count = EXCLUDED.vessel_count,
                    container = EXCLUDED.container,
                    dry_bulk = EXCLUDED.dry_bulk,
                    general_cargo = EXCLUDED.general_cargo,
                    roro = EXCLUDED.roro,
                    tanker = EXCLUDED.tanker,
                    collected_at = EXCLUDED.collected_at,
                    updated_at = NOW()
            """, records, page_size=100)

            conn.commit()
            total_new_records += len(new_df)
            print(f"  ✅ {chokepoint}: Synced {len(new_df)} records")

        except Exception as e:
            conn.rollback()
            print(f"  ❌ Error processing {csv_file.name}: {str(e)}")
            raise

    cursor.close()
    conn.close()

    if total_new_records > 0:
        print(f"[{datetime.now()}] ✅ Incremental sync completed: {total_new_records} new/updated records")
    else:
        print(f"[{datetime.now()}] ✅ No new data to sync")

if __name__ == "__main__":
    load_incremental_csv_to_postgres()
