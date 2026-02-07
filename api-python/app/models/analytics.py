"""
Analytics Data Models
"""
from pydantic import BaseModel
from typing import List, Optional
from datetime import date


class VesselTypeData(BaseModel):
    """Vessel type breakdown"""
    container: int
    dry_bulk: int
    general_cargo: int
    roro: int
    tanker: int


class MonthlyData(BaseModel):
    """Monthly aggregated data"""
    month: str  # YYYY-MM format
    total_vessels: int
    avg_vessels: float
    peak_vessels: int
    min_vessels: int
    vessel_types: VesselTypeData


class TrendResponse(BaseModel):
    """Trend analysis response"""
    chokepoint: str
    years: int
    start_date: str
    end_date: str
    monthly_data: List[MonthlyData]
    summary: dict


class CompareRequest(BaseModel):
    """Compare chokepoints request"""
    chokepoints: List[str]
    metric: str = "vessel_count"
    start_date: Optional[str] = None
    end_date: Optional[str] = None
