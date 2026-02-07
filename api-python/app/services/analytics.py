"""
Analytics Service
Handles complex analytics queries from ClickHouse
"""
from typing import List, Dict, Any
from datetime import datetime, timedelta
from app.database.clickhouse import clickhouse_client
from app.models.analytics import MonthlyData, VesselTypeData, TrendResponse


class AnalyticsService:
    """Analytics service for trend analysis"""

    @staticmethod
    async def get_trend_analysis(chokepoint: str, years: int = 5) -> TrendResponse:
        """
        Get multi-year trend analysis for a chokepoint

        Args:
            chokepoint: Chokepoint name
            years: Number of years to analyze

        Returns:
            TrendResponse with monthly aggregated data
        """
        # Calculate date range
        end_date = datetime.now()
        start_date = end_date - timedelta(days=years * 365)

        # Query monthly summary from ClickHouse
        query = f"""
        SELECT
            toStartOfMonth(date) as month,
            sum(vessel_count) as total_vessels,
            avg(vessel_count) as avg_vessels,
            max(vessel_count) as peak_vessels,
            min(vessel_count) as min_vessels,
            sum(container) as total_containers,
            sum(dry_bulk) as total_dry_bulk,
            sum(general_cargo) as total_general_cargo,
            sum(roro) as total_roro,
            sum(tanker) as total_tankers
        FROM vessel_arrivals_analytics
        WHERE chokepoint = '{chokepoint}'
          AND date >= '{start_date.strftime('%Y-%m-%d')}'
          AND date <= '{end_date.strftime('%Y-%m-%d')}'
        GROUP BY month
        ORDER BY month
        """

        results = await clickhouse_client.execute_query(query)

        # Transform results to response model
        monthly_data = []
        total_vessels_sum = 0
        total_months = len(results)

        for row in results:
            vessel_types = VesselTypeData(
                container=int(row.get('total_containers', 0)),
                dry_bulk=int(row.get('total_dry_bulk', 0)),
                general_cargo=int(row.get('total_general_cargo', 0)),
                roro=int(row.get('total_roro', 0)),
                tanker=int(row.get('total_tankers', 0))
            )

            monthly = MonthlyData(
                month=row['month'],
                total_vessels=int(row['total_vessels']),
                avg_vessels=round(float(row['avg_vessels']), 2),
                peak_vessels=int(row['peak_vessels']),
                min_vessels=int(row['min_vessels']),
                vessel_types=vessel_types
            )
            monthly_data.append(monthly)
            total_vessels_sum += monthly.total_vessels

        # Calculate summary statistics
        summary = {
            "total_vessels": total_vessels_sum,
            "average_monthly_vessels": round(total_vessels_sum / total_months, 2) if total_months > 0 else 0,
            "months_analyzed": total_months,
            "peak_month": max(monthly_data, key=lambda x: x.total_vessels).month if monthly_data else None,
            "lowest_month": min(monthly_data, key=lambda x: x.total_vessels).month if monthly_data else None
        }

        return TrendResponse(
            chokepoint=chokepoint,
            years=years,
            start_date=start_date.strftime('%Y-%m-%d'),
            end_date=end_date.strftime('%Y-%m-%d'),
            monthly_data=monthly_data,
            summary=summary
        )


# Global service instance
analytics_service = AnalyticsService()
