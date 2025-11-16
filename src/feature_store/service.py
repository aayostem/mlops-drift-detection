# src/feature_store/service.py

import pandas as pd
import numpy as np
from feast import FeatureStore
from typing import Dict, List, Optional
import asyncio
from datetime import datetime
import logging
from prometheus_client import Counter, Histogram, Gauge

# Metrics
feature_retrieval_counter = Counter(
    "feature_retrieval_requests_total",
    "Total feature retrieval requests",
    ["feature_view"],
)
feature_retrieval_duration = Histogram(
    "feature_retrieval_duration_seconds", "Feature retrieval duration", ["feature_view"]
)
feature_freshness = Gauge(
    "feature_freshness_seconds", "Feature freshness in seconds", ["feature_view"]
)


class FeatureStoreService:
    def __init__(self, repo_path: str = "./feature-store"):
        self.store = FeatureStore(repo_path=repo_path)
        self.logger = logging.getLogger(__name__)

    @feature_retrieval_duration.time()
    async def get_online_features(
        self, entity_rows: List[Dict], feature_refs: List[str]
    ) -> pd.DataFrame:
        """Retrieve features for online inference"""
        try:
            feature_retrieval_counter.labels(feature_view="online").inc()

            # Convert to DataFrame for Feast
            entity_df = pd.DataFrame(entity_rows)

            # Get features
            features = self.store.get_online_features(
                features=feature_refs, entity_rows=entity_rows
            ).to_df()

            # Update freshness metrics
            await self._update_freshness_metrics(feature_refs)

            self.logger.info(f"Retrieved {len(features)} feature rows")
            return features

        except Exception as e:
            self.logger.error(f"Error retrieving online features: {e}")
            raise

    async def get_historical_features(
        self, entity_df: pd.DataFrame, feature_refs: List[str]
    ) -> pd.DataFrame:
        """Retrieve historical features for training"""
        try:
            feature_retrieval_counter.labels(feature_view="historical").inc()

            # Get historical features
            historical_features = self.store.get_historical_features(
                entity_df=entity_df, features=feature_refs
            ).to_df()

            self.logger.info(
                f"Retrieved {len(historical_features)} historical feature rows"
            )
            return historical_features

        except Exception as e:
            self.logger.error(f"Error retrieving historical features: {e}")
            raise

    async def materialize_features(self, start_date: datetime, end_date: datetime):
        """Materialize features to online store"""
        try:
            self.logger.info(f"Materializing features from {start_date} to {end_date}")

            # Materialize features
            self.store.materialize(start_date=start_date, end_date=end_date)

            self.logger.info("Feature materialization completed successfully")

        except Exception as e:
            self.logger.error(f"Error materializing features: {e}")
            raise

    async def _update_freshness_metrics(self, feature_refs: List[str]):
        """Update feature freshness metrics"""
        try:
            for feature_ref in feature_refs:
                # This would query the actual feature freshness from metadata
                # For now, we'll use a placeholder
                feature_freshness.labels(feature_view=feature_ref).set(0)

        except Exception as e:
            self.logger.warning(f"Could not update freshness metrics: {e}")


# Feature Store API
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="Feature Store Service")
feature_service = FeatureStoreService()


class FeatureRequest(BaseModel):
    entity_rows: List[Dict]
    feature_refs: List[str]


class HistoricalFeatureRequest(BaseModel):
    entity_df: Dict  # JSON representation of DataFrame
    feature_refs: List[str]


@app.post("/features/online")
async def get_online_features(request: FeatureRequest):
    """Get features for online inference"""
    try:
        features = await feature_service.get_online_features(
            request.entity_rows, request.feature_refs
        )
        return features.to_dict("records")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/features/historical")
async def get_historical_features(request: HistoricalFeatureRequest):
    """Get historical features for training"""
    try:
        entity_df = pd.DataFrame(request.entity_df)
        features = await feature_service.get_historical_features(
            entity_df, request.feature_refs
        )
        return features.to_dict("records")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/features/materialize")
async def materialize_features(start_date: str, end_date: str):
    """Trigger feature materialization"""
    try:
        start_dt = datetime.fromisoformat(start_date)
        end_dt = datetime.fromisoformat(end_date)

        await feature_service.materialize_features(start_dt, end_dt)
        return {"status": "success", "message": "Feature materialization completed"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/health")
async def health_check():
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}
