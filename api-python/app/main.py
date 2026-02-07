"""
FastAPI Application
Handles complex analytics and LangGraph Agent
"""
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import Optional, AsyncGenerator
from dotenv import load_dotenv
from prometheus_client import make_asgi_app
import os
import httpx
import json
import asyncio

# Import analytics models and services
from app.models.analytics import TrendResponse, CompareRequest
from app.services.analytics import analytics_service
from app.database.clickhouse import clickhouse_client

# Load environment variables
load_dotenv()

# Initialize FastAPI
app = FastAPI(
    title="SeeSea Analytics API",
    description="Complex analytics and AI agent for maritime intelligence",
    version="2.0.0"
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Add prometheus metrics endpoint
metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)

# Health check
@app.get("/health")
async def health_check():
    return {
        "status": "OK",
        "service": "seesea-api-python",
        "version": "2.0.0"
    }

# Root
@app.get("/")
async def root():
    return {
        "message": "SeeSea Analytics API",
        "docs": "/docs",
        "health": "/health"
    }

# Analytics routes
@app.get("/api/v1/analytics/trend", response_model=TrendResponse)
async def get_trend(chokepoint: str, years: int = 5):
    """
    Multi-year trend analysis for a chokepoint

    Returns monthly aggregated vessel data including:
    - Total vessels per month
    - Average, peak, and minimum daily vessels
    - Breakdown by vessel type (container, tanker, bulk, etc.)
    - Summary statistics

    Args:
        chokepoint: Chokepoint name (e.g., 'suez-canal', 'panama-canal')
        years: Number of years to analyze (default: 5, max: 10)
    """
    try:
        # Validate years parameter
        if years < 1 or years > 10:
            raise HTTPException(
                status_code=400,
                detail="Years parameter must be between 1 and 10"
            )

        # Check ClickHouse connection
        if not await clickhouse_client.ping():
            raise HTTPException(
                status_code=503,
                detail="Analytics database is unavailable"
            )

        # Get trend analysis
        result = await analytics_service.get_trend_analysis(chokepoint, years)
        return result

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Error analyzing trend: {str(e)}"
        )

@app.post("/api/v1/analytics/compare")
async def compare_chokepoints(chokepoints: list[str]):
    """Compare multiple chokepoints"""
    return {
        "chokepoints": chokepoints,
        "message": "Comparison analysis will be implemented"
    }

# Ships/Vessels routes
@app.get("/api/v1/ships")
async def get_ships():
    """Get all ships with real-time positions (mock data for now)"""
    # TODO: Replace with real data from database
    ships = [
        {
            "id": "1",
            "mmsi": "477123456",
            "name": "MAERSK ALPHA",
            "position": {
                "lng": 121.5,
                "lat": 31.2
            },
            "destination": "洛杉磯",
            "cargo": "電子產品",
            "teu": 8000,
            "speed": 18.5,
            "heading": 85,
            "status": "underway",
            "eta": "2024-02-15T10:00:00Z"
        },
        {
            "id": "2",
            "mmsi": "244567890",
            "name": "EVERGREEN BETA",
            "position": {
                "lng": 4.4,
                "lat": 51.9
            },
            "destination": "鹿特丹",
            "cargo": "汽車零件",
            "teu": 12000,
            "speed": 20.2,
            "heading": 270,
            "status": "moored",
            "eta": "2024-02-10T14:30:00Z"
        },
        {
            "id": "3",
            "mmsi": "412789012",
            "name": "COSCO GAMMA",
            "position": {
                "lng": -118.2,
                "lat": 33.7
            },
            "destination": "上海",
            "cargo": "原材料",
            "teu": 14000,
            "speed": 19.8,
            "heading": 310,
            "status": "underway",
            "eta": "2024-02-20T08:00:00Z"
        }
    ]
    return {
        "ships": ships,
        "total": len(ships),
        "timestamp": "2024-02-07T13:00:00Z"
    }

@app.get("/api/v1/ships/{ship_id}")
async def get_ship(ship_id: str):
    """Get specific ship details"""
    # TODO: Query from database
    raise HTTPException(status_code=404, detail="Ship not found")

# ============================================================================
# Request/Response Models
# ============================================================================

class ChatRequest(BaseModel):
    """Chat request model"""
    message: str
    session_id: Optional[str] = None


class ChatResponse(BaseModel):
    """Chat response model"""
    response: str
    session_id: Optional[str] = None


# ============================================================================
# Chat/Agent Routes
# ============================================================================

# Agent server URL
AGENT_SERVER_URL = os.getenv("AGENT_SERVER_URL", "http://localhost:8002")


@app.post("/api/v1/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """
    Chat with LangGraph Agent (non-streaming)
    Proxies request to the AI Agent server
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{AGENT_SERVER_URL}/chat",
                json={
                    "message": request.message,
                    "session_id": request.session_id
                },
                timeout=60.0
            )
            response.raise_for_status()
            data = response.json()
            return ChatResponse(
                response=data.get("response", ""),
                session_id=data.get("session_id")
            )
    except httpx.HTTPError as e:
        raise HTTPException(
            status_code=500,
            detail=f"Error communicating with agent: {str(e)}"
        ) from e


@app.post("/api/v1/chat/stream")
async def chat_stream(request: ChatRequest):
    """
    Chat with LangGraph Agent using Server-Sent Events (SSE)
    Proxies SSE stream from AI Agent server to frontend

    Returns streaming events:
    - event: tool_call - When agent calls a tool
    - event: tool_result - Result from tool execution
    - event: content - AI response content (streamed)
    - event: done - Stream complete
    - event: error - Error occurred
    """
    async def event_stream() -> AsyncGenerator[str, None]:
        try:
            # Connect to agent server SSE stream
            async with httpx.AsyncClient(timeout=120.0) as client:
                async with client.stream(
                    "POST",
                    f"{AGENT_SERVER_URL}/chat/stream",
                    json={
                        "message": request.message,
                        "session_id": request.session_id
                    }
                ) as response:
                    response.raise_for_status()

                    # Forward SSE events from agent to frontend
                    async for line in response.aiter_lines():
                        if line:
                            yield f"{line}\n"
                            await asyncio.sleep(0)  # Allow other tasks to run
                        else:
                            # Empty line (SSE message separator)
                            yield "\n"

        except httpx.HTTPError as e:
            yield f"event: error\n"
            yield f"data: {json.dumps({'error': f'Agent connection error: {str(e)}'})}\n\n"
        except Exception as e:
            yield f"event: error\n"
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no"
        }
    )

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run(app, host="0.0.0.0", port=port)
