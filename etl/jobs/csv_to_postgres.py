"""
CSV to PostgreSQL ETL Job
Reads CSV files and loads into PostgreSQL
"""
import os
import pandas as pd
import psycopg2
from dotenv import load_dotenv
from pathlib import Path

load_dotenv()

def load_csv_to_postgres():
    """Load all CSV files to PostgreSQL"""

    # Database connection
    conn = psycopg2.connect(os.getenv('DATABASE_URL'))
    cursor = conn.cursor()

    # Find all CSV files
    base_path = Path(__file__).parent.parent.parent / 'processed' / 'logistics' / 'chokepoints'

    csv_files = list(base_path.glob('*/vessel_arrivals/vessel_arrivals.csv'))

    print(f"Found {len(csv_files)} CSV files")

    for csv_file in csv_files:
        print(f"Processing: {csv_file}")

        # Read CSV
        df = pd.read_csv(csv_file)

        # Insert into PostgreSQL
        for _, row in df.iterrows():
            cursor.execute("""
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
            """, (
                row['date'],
                row['chokepoint'],
                row['vessel_count'],
                row['container'],
                row['dry_bulk'],
                row['general_cargo'],
                row['roro'],
                row['tanker'],
                row['collected_at']
            ))

        conn.commit()
        print(f"✅ Loaded {len(df)} records from {csv_file.name}")

    cursor.close()
    conn.close()

    print("✅ All CSV files loaded to PostgreSQL")

if __name__ == "__main__":
    load_csv_to_postgres()
