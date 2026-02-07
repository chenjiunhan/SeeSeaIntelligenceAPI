"""
ClickHouse Database Connection
"""
import os
from typing import Optional, Dict, List, Any
import httpx
from dotenv import load_dotenv

load_dotenv()

class ClickHouseClient:
    """ClickHouse HTTP client for analytics queries"""

    def __init__(self):
        self.url = os.getenv("CLICKHOUSE_URL", "http://localhost:8123")
        self.database = "seesea_analytics"
        self.timeout = 30.0

    async def execute_query(self, query: str, params: Optional[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
        """
        Execute a query and return results as list of dictionaries

        Args:
            query: SQL query string
            params: Optional parameters for query

        Returns:
            List of dictionaries with query results
        """
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            # Format query with database
            full_query = f"USE {self.database};\n{query}"

            # Execute query with JSON format
            response = await client.post(
                self.url,
                params={
                    "query": full_query,
                    "default_format": "JSONEachRow"
                }
            )
            response.raise_for_status()

            # Parse JSON lines response
            results = []
            for line in response.text.strip().split('\n'):
                if line:
                    import json
                    results.append(json.loads(line))

            return results

    async def ping(self) -> bool:
        """Check if ClickHouse is accessible"""
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.get(f"{self.url}/ping")
                return response.status_code == 200
        except Exception:
            return False


# Global instance
clickhouse_client = ClickHouseClient()
