# src/api/config.py
from pydantic import BaseSettings
from typing import List


class APISettings(BaseSettings):
    """API configuration settings"""

    # Server settings
    host: str = "0.0.0.0"
    port: int = 8000
    workers: int = 4
    reload: bool = False  # Set to False in production

    # Security
    cors_origins: List[str] = ["http://localhost:3000"]
    allowed_hosts: List[str] = ["localhost", "127.0.0.1"]

    # Model settings
    model_name: str = "breast-cancer-classifier"
    fallback_to_staging: bool = True

    # Monitoring
    metrics_enabled: bool = True
    log_level: str = "INFO"

    class Config:
        env_file = ".env"
        env_prefix = "API_"


api_settings = APISettings()
