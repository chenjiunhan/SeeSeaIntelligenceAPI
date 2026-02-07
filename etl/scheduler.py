"""
ETL Scheduler
Runs daily data synchronization tasks
"""
import os
import sys
from pathlib import Path
from apscheduler.schedulers.blocking import BlockingScheduler
from apscheduler.triggers.cron import CronTrigger
from datetime import datetime
from dotenv import load_dotenv

# Add jobs directory to path
sys.path.insert(0, str(Path(__file__).parent / 'jobs'))

load_dotenv()

def csv_to_postgres():
    """Sync CSV files to PostgreSQL (incremental)"""
    print(f"[{datetime.now()}] Running incremental CSV → PostgreSQL sync...")
    try:
        from jobs.incremental_csv_to_postgres import load_incremental_csv_to_postgres
        load_incremental_csv_to_postgres()
        print(f"[{datetime.now()}] ✅ Incremental CSV sync completed")
    except Exception as e:
        print(f"[{datetime.now()}] ❌ CSV sync failed: {str(e)}")

def pg_to_clickhouse():
    """Sync PostgreSQL to ClickHouse"""
    print(f"[{datetime.now()}] Running PostgreSQL → ClickHouse sync...")
    try:
        from jobs.pg_to_clickhouse import sync_to_clickhouse
        sync_to_clickhouse()
        print(f"[{datetime.now()}] ✅ ClickHouse sync completed")
    except Exception as e:
        print(f"[{datetime.now()}] ❌ ClickHouse sync failed: {str(e)}")

def main():
    scheduler = BlockingScheduler()

    # CSV to PostgreSQL: Every hour
    scheduler.add_job(
        csv_to_postgres,
        trigger=CronTrigger(minute=0),
        id='csv_to_postgres',
        name='CSV to PostgreSQL sync'
    )

    # PostgreSQL to ClickHouse: Daily at 2 AM
    scheduler.add_job(
        pg_to_clickhouse,
        trigger=CronTrigger(hour=2, minute=0),
        id='pg_to_clickhouse',
        name='PostgreSQL to ClickHouse sync'
    )

    print("📅 ETL Scheduler started")
    print("Jobs:")
    for job in scheduler.get_jobs():
        print(f"  - {job.name}")

    scheduler.start()

if __name__ == "__main__":
    main()
