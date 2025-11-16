# src/config/settings.py
from pydantic import BaseSettings
from typing import Optional
import os


class MLflowSettings(BaseSettings):
    tracking_uri: str = "http://localhost:5000"
    registry_uri: str = "http://localhost:5000"
    experiment_name: str = "breast-cancer-detection"


class PrefectSettings(BaseSettings):
    api_url: str = "http://localhost:4200/api"
    work_queue_name: str = "ml-training"


class ModelSettings(BaseSettings):
    model_name: str = "breast-cancer-classifier"
    validation_metric: str = "f1_score"
    validation_threshold: float = 0.85


class Settings(BaseSettings):
    mlflow: MLflowSettings = MLflowSettings()
    prefect: PrefectSettings = PrefectSettings()
    model: ModelSettings = ModelSettings()

    class Config:
        env_file = ".env"
        env_nested_delimiter = "__"


settings = Settings()
