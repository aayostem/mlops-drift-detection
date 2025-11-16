# src/data/pipeline.py
import pandas as pd
import numpy as np
from prefect import flow, task
from prefect.blocks.system import JSON
from prefect.logging import get_run_logger
from sklearn.datasets import load_breast_cancer
from sklearn.model_selection import train_test_split
from typing import Tuple, Dict, Any
import mlflow
import json
from datetime import datetime


@task(retries=3, retry_delay_seconds=10)
def load_and_validate_data() -> pd.DataFrame:
    """Load data with comprehensive validation"""
    logger = get_run_logger()

    try:
        # Simulate enterprise data source
        data = load_breast_cancer()
        df = pd.DataFrame(data.data, columns=data.feature_names)
        df["target"] = data.target

        # Data quality checks
        assert len(df) > 0, "Dataframe is empty"
        assert not df.isnull().any().any(), "Null values detected"
        assert df["target"].isin([0, 1]).all(), "Invalid target values"

        logger.info(
            f"Data loaded successfully: {len(df)} rows, {len(df.columns)} columns"
        )
        return df

    except Exception as e:
        logger.error(f"Data loading failed: {str(e)}")
        raise


@task
def feature_engineering(df: pd.DataFrame) -> pd.DataFrame:
    """Create features with business logic"""
    logger = get_run_logger()

    # Create interaction features
    df["mean_radius_texture"] = df["mean radius"] * df["mean texture"]
    df["worst_area_perimeter"] = df["worst area"] / (df["worst perimeter"] + 1e-5)

    # Create statistical aggregates
    mean_features = [col for col in df.columns if "mean" in col]
    df["mean_features_avg"] = df[mean_features].mean(axis=1)
    df["mean_features_std"] = df[mean_features].std(axis=1)

    logger.info("Feature engineering completed")
    return df


@task
def train_test_split_task(df: pd.DataFrame, test_size: float = 0.2) -> Tuple:
    """Stratified train-test split with logging"""
    logger = get_run_logger()

    X = df.drop("target", axis=1)
    y = df["target"]

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=test_size, stratify=y, random_state=42
    )

    logger.info(f"Train set: {len(X_train)} samples, Test set: {len(X_test)} samples")
    return X_train, X_test, y_train, y_test


@flow(name="ml-data-pipeline", version="1.0")
def data_pipeline_flow() -> Dict[str, Any]:
    """Main data pipeline flow"""
    logger = get_run_logger()

    try:
        # Load and validate data
        raw_data = load_and_validate_data()

        # Feature engineering
        processed_data = feature_engineering(raw_data)

        # Train-test split
        X_train, X_test, y_train, y_test = train_test_split_task(processed_data)

        # Log dataset statistics
        dataset_info = {
            "timestamp": datetime.utcnow().isoformat(),
            "total_samples": len(processed_data),
            "train_samples": len(X_train),
            "test_samples": len(X_test),
            "feature_count": len(processed_data.columns) - 1,
            "class_distribution": processed_data["target"].value_counts().to_dict(),
        }

        logger.info("Data pipeline completed successfully", extra=dataset_info)

        return {
            "X_train": X_train,
            "X_test": X_test,
            "y_train": y_train,
            "y_test": y_test,
            "dataset_info": dataset_info,
        }

    except Exception as e:
        logger.error(f"Data pipeline failed: {str(e)}")
        raise
