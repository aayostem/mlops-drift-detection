# src/models/training.py
import mlflow
import mlflow.sklearn
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.svm import SVC
from sklearn.metrics import (
    accuracy_score,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.model_selection import cross_val_score
import numpy as np
from typing import Dict, Any, List
from prefect import task
import joblib
import json


@task
def train_and_evaluate_models(
    X_train, X_test, y_train, y_test, dataset_info: Dict
) -> Dict:
    """Train multiple models with comprehensive evaluation"""
    logger = get_run_logger()

    # Define models to evaluate
    models = {
        "random_forest": RandomForestClassifier(n_estimators=100, random_state=42),
        "gradient_boosting": GradientBoostingClassifier(
            n_estimators=100, random_state=42
        ),
        "svm": SVC(probability=True, random_state=42),
    }

    best_score = -1
    best_model = None
    best_model_name = None

    # Set MLflow experiment
    mlflow.set_experiment("breast-cancer-detection")

    with mlflow.start_run(run_name="model_comparison"):
        # Log dataset info
        mlflow.log_dict(dataset_info, "dataset_info.json")

        results = {}

        for model_name, model in models.items():
            with mlflow.start_run(run_name=model_name, nested=True):
                # Train model
                model.fit(X_train, y_train)

                # Predictions
                y_pred = model.predict(X_test)
                y_pred_proba = (
                    model.predict_proba(X_test)[:, 1]
                    if hasattr(model, "predict_proba")
                    else None
                )

                # Calculate metrics
                metrics = {
                    "accuracy": accuracy_score(y_test, y_pred),
                    "f1_score": f1_score(y_test, y_pred),
                    "precision": precision_score(y_test, y_pred),
                    "recall": recall_score(y_test, y_pred),
                }

                if y_pred_proba is not None:
                    metrics["roc_auc"] = roc_auc_score(y_test, y_pred_proba)

                # Cross-validation
                cv_scores = cross_val_score(model, X_train, y_train, cv=5, scoring="f1")
                metrics["cv_f1_mean"] = cv_scores.mean()
                metrics["cv_f1_std"] = cv_scores.std()

                # Log parameters
                mlflow.log_params(model.get_params())

                # Log metrics
                mlflow.log_metrics(metrics)

                # Log model
                mlflow.sklearn.log_model(model, model_name)

                # Log feature importance if available
                if hasattr(model, "feature_importances_"):
                    feature_importance = dict(
                        zip(X_train.columns, model.feature_importances_)
                    )
                    mlflow.log_dict(
                        feature_importance, f"feature_importance_{model_name}.json"
                    )

                results[model_name] = {
                    "model": model,
                    "metrics": metrics,
                    "cv_scores": cv_scores.tolist(),
                }

                # Track best model
                if metrics["f1_score"] > best_score:
                    best_score = metrics["f1_score"]
                    best_model = model
                    best_model_name = model_name

        # Register best model
        if best_model and best_score > 0.8:  # Quality threshold
            mlflow.sklearn.log_model(
                best_model,
                "best_model",
                registered_model_name="breast-cancer-classifier",
            )

            logger.info(
                f"Best model: {best_model_name} with F1 score: {best_score:.4f}"
            )

        return {
            "best_model": best_model,
            "best_model_name": best_model_name,
            "best_score": best_score,
            "all_results": results,
        }


@task
def register_model_in_registry(
    model, model_name: str, metrics: Dict, version: str = "1.0.0"
):
    """Register model in MLflow model registry with versioning"""

    # Log model with metadata
    mlflow.sklearn.log_model(
        model,
        artifact_path="model",
        registered_model_name=model_name,
        metadata={
            "version": version,
            "metrics": json.dumps(metrics),
            "framework": "scikit-learn",
        },
    )

    # Transition model to staging
    client = mlflow.tracking.MlflowClient()
    latest_version = client.get_latest_versions(model_name, stages=["None"])[0].version

    client.transition_model_version_stage(
        name=model_name, version=latest_version, stage="Staging"
    )
