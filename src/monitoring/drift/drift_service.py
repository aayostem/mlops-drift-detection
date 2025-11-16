# src/monitoring/drift/drift_service.py

import asyncio
import pandas as pd
import numpy as np
from typing import Dict, List
from fastapi import FastAPI, BackgroundTasks
from pydantic import BaseModel
import prometheus_client as prom
from datetime import datetime, timedelta
import mlflow
import json
import logging

# Prometheus metrics
drift_score = prom.Gauge("drift_score", "Current drift score", ["model_name"])
drift_detected = prom.Gauge("drift_detected", "Drift detection status", ["model_name"])
feature_drift_scores = prom.Gauge(
    "feature_drift_score", "Feature-level drift scores", ["model_name", "feature_name"]
)


class DriftDetectionRequest(BaseModel):
    model_name: str
    current_data: List[Dict]
    reference_data_id: str
    detection_config: Dict = {}


class DriftDetectionResponse(BaseModel):
    drift_detected: bool
    drift_score: float
    drift_type: str
    features_affected: List[str]
    confidence: float
    recommendation: str


app = FastAPI(title="ML Drift Detection Service")


class DriftDetectionService:
    def __init__(self):
        self.detectors = {}
        self.reference_data_cache = {}
        self.setup_prometheus_metrics()

    def setup_prometheus_metrics(self):
        """Initialize Prometheus metrics"""
        pass  # Metrics already defined above

    async def detect_drift(
        self, request: DriftDetectionRequest
    ) -> DriftDetectionResponse:
        """Detect drift for incoming data"""

        # Convert to DataFrame
        current_df = pd.DataFrame(request.current_data)

        # Load reference data
        reference_df = await self.load_reference_data(request.reference_data_id)

        # Get or create detector
        detector = self.detectors.get(request.model_name)
        if detector is None:
            detector = MultiModalDriftDetector(request.detection_config)
            self.detectors[request.model_name] = detector

        # Detect drift
        result = detector.detect_drift(reference_df, current_df)

        # Update Prometheus metrics
        self.update_metrics(request.model_name, result, current_df.columns)

        # Log to MLflow
        await self.log_to_mlflow(request.model_name, result)

        # Generate recommendation
        recommendation = self.generate_recommendation(result)

        return DriftDetectionResponse(
            drift_detected=result.drift_detected,
            drift_score=result.drift_score,
            drift_type=result.drift_type,
            features_affected=result.features_affected,
            confidence=result.confidence,
            recommendation=recommendation,
        )

    async def load_reference_data(self, reference_data_id: str) -> pd.DataFrame:
        """Load reference data from MLflow or cache"""
        if reference_data_id in self.reference_data_cache:
            return self.reference_data_cache[reference_data_id]

        # Load from MLflow
        try:
            client = mlflow.tracking.MlflowClient()
            # Implementation to load reference data from MLflow
            # This would typically load the training dataset for the model
            reference_df = pd.DataFrame()  # Placeholder
            self.reference_data_cache[reference_data_id] = reference_df
            return reference_df
        except Exception as e:
            logging.error(f"Error loading reference data: {e}")
            raise

    def update_metrics(self, model_name: str, result: DriftResult, features: List[str]):
        """Update Prometheus metrics"""
        drift_score.labels(model_name=model_name).set(result.drift_score)
        drift_detected.labels(model_name=model_name).set(int(result.drift_detected))

        # Update feature-level metrics
        for feature in features:
            # In a real implementation, you'd have feature-specific scores
            feature_drift_scores.labels(
                model_name=model_name, feature_name=feature
            ).set(
                result.drift_score * np.random.uniform(0.8, 1.2)
            )  # Simulated

    async def log_to_mlflow(self, model_name: str, result: DriftResult):
        """Log drift detection results to MLflow"""
        try:
            with mlflow.start_run(
                run_name=f"drift_detection_{datetime.now().isoformat()}"
            ):
                mlflow.log_metric("drift_score", result.drift_score)
                mlflow.log_metric("drift_detected", int(result.drift_detected))
                mlflow.log_param("drift_type", result.drift_type)
                mlflow.log_param(
                    "features_affected", json.dumps(result.features_affected)
                )

                # Log detailed results
                mlflow.log_dict(result.metadata, "drift_detection_details.json")
        except Exception as e:
            logging.warning(f"Failed to log to MLflow: {e}")

    def generate_recommendation(self, result: DriftResult) -> str:
        """Generate actionable recommendations based on drift detection"""
        if not result.drift_detected:
            return "No action needed. Model performance is stable."

        recommendations = []

        if "covariate_drift" in result.drift_type:
            recommendations.append(
                f"Retrain model with new data distribution. {len(result.features_affected)} features affected."
            )

        if "concept_drift" in result.drift_type:
            recommendations.append(
                "Consider updating model architecture or features to adapt to concept drift."
            )

        if result.drift_score > 0.8:
            recommendations.append(
                "URGENT: Significant drift detected. Consider immediate model retraining and evaluation."
            )

        if result.features_affected:
            recommendations.append(
                f"Focus on features: {', '.join(result.features_affected[:5])}"
            )

        return " | ".join(recommendations) if recommendations else "Monitor closely."


# Global service instance
drift_service = DriftDetectionService()


@app.post("/detect-drift", response_model=DriftDetectionResponse)
async def detect_drift_endpoint(request: DriftDetectionRequest):
    """Endpoint for drift detection"""
    return await drift_service.detect_drift(request)


@app.get("/metrics")
async def metrics_endpoint():
    """Prometheus metrics endpoint"""
    return prom.generate_latest()


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8080)
