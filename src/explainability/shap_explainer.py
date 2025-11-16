# src/explainability/shap_explainer.py

import shap
import pandas as pd
import numpy as np
from typing import Dict, List, Any, Optional
import mlflow
from prometheus_client import Counter, Histogram
import logging
import json

# Metrics
explanation_requests = Counter(
    "explanation_requests_total", "Total explanation requests", ["model_name"]
)
explanation_duration = Histogram(
    "explanation_duration_seconds", "Explanation generation duration", ["model_name"]
)


class SHAPExplainabilityService:
    def __init__(self):
        self.explainers = {}
        self.logger = logging.getLogger(__name__)

    async def load_explainer(self, model_uri: str, background_data: pd.DataFrame):
        """Load SHAP explainer for a model"""
        try:
            if model_uri in self.explainers:
                return self.explainers[model_uri]

            # Load model
            model = mlflow.pyfunc.load_model(model_uri)

            # Create explainer
            if hasattr(model, "predict_proba"):
                # For classification models
                explainer = shap.TreeExplainer(model, background_data)
            else:
                # For regression models
                explainer = shap.TreeExplainer(model, background_data)

            self.explainers[model_uri] = explainer
            self.logger.info(f"Loaded SHAP explainer for model: {model_uri}")

            return explainer

        except Exception as e:
            self.logger.error(f"Error loading SHAP explainer: {e}")
            raise

    @explanation_duration.time()
    async def explain_prediction(
        self, model_uri: str, input_data: pd.DataFrame, background_data: pd.DataFrame
    ) -> Dict[str, Any]:
        """Generate SHAP explanation for a prediction"""
        try:
            explanation_requests.labels(model_name=model_uri.split("/")[-1]).inc()

            # Load explainer
            explainer = await self.load_explainer(model_uri, background_data)

            # Generate SHAP values
            shap_values = explainer.shap_values(input_data)

            # For classification models, get the explanation for the predicted class
            if isinstance(shap_values, list):
                # Multi-class classification
                predicted_class = np.argmax(explainer.model.predict(input_data))
                shap_values = shap_values[predicted_class]

            # Create explanation
            explanation = {
                "shap_values": (
                    shap_values.tolist()
                    if hasattr(shap_values, "tolist")
                    else shap_values
                ),
                "base_value": float(explainer.expected_value),
                "feature_names": input_data.columns.tolist(),
                "feature_importance": self._calculate_feature_importance(
                    shap_values, input_data.columns
                ),
                "local_explanation": self._create_local_explanation(
                    shap_values, input_data
                ),
                "global_insights": await self._generate_global_insights(
                    explainer, background_data
                ),
            }

            return explanation

        except Exception as e:
            self.logger.error(f"Error generating SHAP explanation: {e}")
            raise

    def _calculate_feature_importance(
        self, shap_values: np.ndarray, feature_names: List[str]
    ) -> List[Dict]:
        """Calculate feature importance from SHAP values"""
        if len(shap_values.shape) > 1:
            # For multi-row explanations, take mean absolute impact
            importance_scores = np.mean(np.abs(shap_values), axis=0)
        else:
            importance_scores = np.abs(shap_values)

        feature_importance = []
        for i, feature in enumerate(feature_names):
            feature_importance.append(
                {
                    "feature": feature,
                    "importance": float(importance_scores[i]),
                    "direction": (
                        "positive"
                        if np.mean(
                            shap_values[:, i]
                            if len(shap_values.shape) > 1
                            else shap_values[i]
                        )
                        > 0
                        else "negative"
                    ),
                }
            )

        # Sort by importance
        feature_importance.sort(key=lambda x: x["importance"], reverse=True)
        return feature_importance

    def _create_local_explanation(
        self, shap_values: np.ndarray, input_data: pd.DataFrame
    ) -> List[Dict]:
        """Create local explanation for each feature"""
        local_explanation = []

        for i, feature in enumerate(input_data.columns):
            feature_value = (
                input_data.iloc[0, i]
                if len(input_data) == 1
                else input_data.iloc[:, i].mean()
            )
            shap_value = (
                shap_values[i] if len(shap_values.shape) == 1 else shap_values[0, i]
            )

            local_explanation.append(
                {
                    "feature": feature,
                    "value": float(feature_value),
                    "shap_value": float(shap_value),
                    "impact": "increases" if shap_value > 0 else "decreases",
                }
            )

        return local_explanation

    async def _generate_global_insights(
        self, explainer: shap.TreeExplainer, background_data: pd.DataFrame
    ) -> Dict[str, Any]:
        """Generate global model insights"""
        try:
            # Calculate global feature importance
            global_shap_values = explainer.shap_values(background_data)

            if isinstance(global_shap_values, list):
                global_shap_values = global_shap_values[
                    0
                ]  # Take first class for global importance

            global_importance = np.mean(np.abs(global_shap_values), axis=0)

            # Feature interactions (simplified)
            interactions = {}
            if hasattr(explainer, "interaction_values"):
                try:
                    interaction_values = explainer.interaction_values(
                        background_data[:100]
                    )  # Sample for performance
                    if interaction_values is not None:
                        interactions = self._calculate_interactions(
                            interaction_values, background_data.columns
                        )
                except Exception as e:
                    self.logger.warning(f"Could not calculate interactions: {e}")

            return {
                "global_feature_importance": dict(
                    zip(background_data.columns, global_importance.tolist())
                ),
                "feature_interactions": interactions,
                "model_complexity": f"{len(background_data.columns)} features",
            }

        except Exception as e:
            self.logger.warning(f"Could not generate global insights: {e}")
            return {}

    def _calculate_interactions(
        self, interaction_values: np.ndarray, feature_names: List[str]
    ) -> Dict[str, Any]:
        """Calculate feature interactions"""
        # Calculate mean absolute interaction strength
        interaction_strength = np.mean(np.abs(interaction_values), axis=0)

        interactions = {}
        for i in range(len(feature_names)):
            for j in range(i + 1, len(feature_names)):
                strength = interaction_strength[i, j]
                if strength > 0.01:  # Threshold for significant interactions
                    key = f"{feature_names[i]}_{feature_names[j]}"
                    interactions[key] = {
                        "features": [feature_names[i], feature_names[j]],
                        "strength": float(strength),
                    }

        return interactions


# FastAPI Service for Explainability
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="Model Explainability Service")
explainability_service = SHAPExplainabilityService()


class ExplanationRequest(BaseModel):
    model_uri: str
    input_data: List[Dict]
    background_data: List[Dict]


@app.post("/explain")
async def explain_prediction(request: ExplanationRequest):
    """Generate explanation for model prediction"""
    try:
        input_df = pd.DataFrame(request.input_data)
        background_df = pd.DataFrame(request.background_data)

        explanation = await explainability_service.explain_prediction(
            request.model_uri, input_df, background_df
        )

        return explanation

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/health")
async def health_check():
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}
