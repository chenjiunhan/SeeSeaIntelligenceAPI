"""
CSV to PostgreSQL ETL Job
Reads CSV files and loads into PostgreSQL
"""
import os
from pathlib import Path

import pandas as pd
import psycopg2
from psycopg2.extras import execute_batch
from dotenv import load_dotenv

load_dotenv()

def load_csv_to_postgres():
    """Load all CSV files to PostgreSQL"""

    # Database connection
    conn = psycopg2.connect(os.getenv('DATABASE_URL'))
    cursor = conn.cursor()

    # Find all CSV files from SeeSeaIntelligence repo
    # Path: ../../SeeSeaIntelligence/processed/logistics/chokepoints/
    base_path = Path(__file__).parent.parent.parent.parent / 'SeeSeaIntelligence' / 'processed' / 'logistics' / 'chokepoints'

    if not base_path.exists():
        raise FileNotFoundError(f"CSV directory not found: {base_path}")

    csv_files = list(base_path.glob('*/vessel_arrivals/vessel_arrivals.csv'))

    print(f"Found {len(csv_files)} CSV files")

    total_records = 0

    for csv_file in csv_files:
        print(f"Processing: {csv_file}")

        try:
            # Read CSV
            df = pd.read_csv(csv_file)

            # Prepare batch data
            records = []
            for _, row in df.iterrows():
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

            # Batch insert for better performance
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
                    collected_at = EXCLUDED.collected_at
            """, records, page_size=100)

            conn.commit()
            total_records += len(df)
            print(f"✅ Loaded {len(df)} records from {csv_file.name}")

        except Exception as e:
            conn.rollback()
            print(f"❌ Error processing {csv_file.name}: {str(e)}")
            raise

    cursor.close()
    conn.close()

    print(f"✅ Successfully loaded {total_records} total records from {len(csv_files)} CSV files to PostgreSQL")

if __name__ == "__main__":
    load_csv_to_postgres()
