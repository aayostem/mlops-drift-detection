# src/api/main.py
from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
import mlflow.pyfunc
import pandas as pd
import numpy as np
from pydantic import BaseModel, validator
from typing import List, Optional, Dict, Any
import logging
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from starlette.requests import Request
from starlette.responses import Response
import time
import os

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prometheus metrics
PREDICTION_COUNTER = Counter(
    "model_predictions_total", "Total predictions", ["model", "version", "status"]
)
PREDICTION_LATENCY = Histogram(
    "prediction_latency_seconds", "Prediction latency in seconds"
)
ERROR_COUNTER = Counter(
    "model_errors_total", "Total prediction errors", ["model", "error_type"]
)

app = FastAPI(
    title="MLOps Drift Detection API",
    description="Enterprise-grade ML model serving with drift detection",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# Security middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "https://yourdomain.com",
    ],  # Configure for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_middleware(
    TrustedHostMiddleware,
    allowed_hosts=["localhost", "yourdomain.com", "*.yourdomain.com"],
)


# Pydantic models for request/response validation
class PredictionRequest(BaseModel):
    features: List[float]
    feature_names: Optional[List[str]] = None
    request_id: Optional[str] = None

    @validator("features")
    def validate_features_length(cls, v):
        if len(v) != 30:  # Breast cancer dataset has 30 features
            raise ValueError(f"Expected 30 features, got {len(v)}")
        return v


class PredictionResponse(BaseModel):
    prediction: int
    probabilities: List[float]
    model_version: str
    request_id: Optional[str] = None
    drift_detected: bool = False


class HealthResponse(BaseModel):
    status: str
    model_loaded: bool
    model_version: str
    timestamp: str


class ModelManager:
    """Manages model loading and versioning"""

    def __init__(self):
        self.model = None
        self.model_version = None
        self.model_name = "breast-cancer-classifier"
        self.load_model()

    def load_model(self):
        """Load the latest production model from MLflow"""
        try:
            model_uri = f"models:/{self.model_name}/Production"
            self.model = mlflow.pyfunc.load_model(model_uri)

            # Get model version
            client = mlflow.tracking.MlflowClient()
            latest_version = client.get_latest_versions(
                self.model_name, stages=["Production"]
            )[0]
            self.model_version = latest_version.version

            logger.info(f"Loaded model {self.model_name} version {self.model_version}")

        except Exception as e:
            logger.error(f"Failed to load model: {str(e)}")
            # Fallback to staging model
            try:
                model_uri = f"models:/{self.model_name}/Staging"
                self.model = mlflow.pyfunc.load_model(model_uri)
                client = mlflow.tracking.MlflowClient()
                latest_version = client.get_latest_versions(
                    self.model_name, stages=["Staging"]
                )[0]
                self.model_version = latest_version.version
                logger.info(f"Loaded staging model version {self.model_version}")
            except Exception as fallback_error:
                logger.error(f"Failed to load fallback model: {str(fallback_error)}")
                self.model = None
                self.model_version = "none"


model_manager = ModelManager()


# Dependency injection for model
def get_model():
    if model_manager.model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")
    return model_manager.model


@app.on_event("startup")
async def startup_event():
    """Initialize services on startup"""
    logger.info("Starting MLOps API Server")


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint with model status"""
    return HealthResponse(
        status="healthy",
        model_loaded=model_manager.model is not None,
        model_version=model_manager.model_version or "none",
        timestamp=pd.Timestamp.now().isoformat(),
    )


@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.post("/predict", response_model=PredictionResponse)
async def predict(request: PredictionRequest, model=Depends(get_model)):
    """Make predictions with drift detection"""
    start_time = time.time()

    try:
        # Convert features to DataFrame
        if request.feature_names:
            feature_df = pd.DataFrame([request.features], columns=request.feature_names)
        else:
            # Use default feature names from breast cancer dataset
            feature_names = [
                "mean radius",
                "mean texture",
                "mean perimeter",
                "mean area",
                "mean smoothness",
                "mean compactness",
                "mean concavity",
                "mean concave points",
                "mean symmetry",
                "mean fractal dimension",
                "radius error",
                "texture error",
                "perimeter error",
                "area error",
                "smoothness error",
                "compactness error",
                "concavity error",
                "concave points error",
                "symmetry error",
                "fractal dimension error",
                "worst radius",
                "worst texture",
                "worst perimeter",
                "worst area",
                "worst smoothness",
                "worst compactness",
                "worst concavity",
                "worst concave points",
                "worst symmetry",
                "worst fractal dimension",
            ]
            feature_df = pd.DataFrame([request.features], columns=feature_names)

        # Make prediction
        prediction = model.predict(feature_df)
        probabilities = (
            model.predict_proba(feature_df)[0].tolist()
            if hasattr(model, "predict_proba")
            else []
        )

        # Check for data drift (simplified - we'll enhance this later)
        drift_detected = await check_drift_detection(feature_df)

        # Log successful prediction
        PREDICTION_COUNTER.labels(
            model=model_manager.model_name,
            version=model_manager.model_version,
            status="success",
        ).inc()

        latency = time.time() - start_time
        PREDICTION_LATENCY.observe(latency)

        logger.info(
            f"Prediction successful - Request: {request.request_id}, Drift: {drift_detected}"
        )

        return PredictionResponse(
            prediction=int(prediction[0]),
            probabilities=probabilities,
            model_version=model_manager.model_version,
            request_id=request.request_id,
            drift_detected=drift_detected,
        )

    except Exception as e:
        # Log error
        ERROR_COUNTER.labels(
            model=model_manager.model_name, error_type=type(e).__name__
        ).inc()

        PREDICTION_COUNTER.labels(
            model=model_manager.model_name,
            version=model_manager.model_version,
            status="error",
        ).inc()

        logger.error(f"Prediction failed: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Prediction failed: {str(e)}")


async def check_drift_detection(feature_df: pd.DataFrame) -> bool:
    """Check if data drift is detected"""
    # This will be integrated with Evidently AI in the next phase
    # For now, return False
    return False


@app.get("/model/info")
async def model_info():
    """Get current model information"""
    if model_manager.model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")

    client = mlflow.tracking.MlflowClient()
    model_version = client.get_model_version(
        model_manager.model_name, model_manager.model_version
    )

    return {
        "model_name": model_manager.model_name,
        "model_version": model_manager.model_version,
        "run_id": model_version.run_id,
        "current_stage": model_version.current_stage,
        "description": model_version.description,
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info", access_log=True)
