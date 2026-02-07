"""
ETL Scheduler
Runs daily data synchronization tasks
"""
import os
from apscheduler.schedulers.blocking import BlockingScheduler
from apscheduler.triggers.cron import CronTrigger
from datetime import datetime
from dotenv import load_dotenv

load_dotenv()

def csv_to_postgres():
    """Sync CSV files to PostgreSQL"""
    print(f"[{datetime.now()}] Running CSV → PostgreSQL sync...")
    # TODO: Implement CSV to PostgreSQL sync
    print("CSV sync completed")

def pg_to_clickhouse():
    """Sync PostgreSQL to ClickHouse"""
    print(f"[{datetime.now()}] Running PostgreSQL → ClickHouse sync...")
    # TODO: Implement PostgreSQL to ClickHouse sync
    print("ClickHouse sync completed")

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
