"""Shared pytest fixtures and configuration"""
import pytest
import os
from unittest.mock import Mock, patch
import tempfile

@pytest.fixture(autouse=True)
def mock_mlflow_tracking():
    """Mock MLflow tracking to avoid real server calls during tests"""
    with tempfile.TemporaryDirectory() as tmpdir:
        with patch('mlflow.set_tracking_uri') as mock_set:
            with patch('mlflow.get_tracking_uri') as mock_get:
                mock_get.return_value = f"file://{tmpdir}/mlruns"
                yield

@pytest.fixture
def mock_model():
    """Create a mock model for testing"""
    mock_model = Mock()
    mock_model.predict.return_value = [0, 1, 0]
    return mock_model

@pytest.fixture
def sample_training_data():
    """Sample data for testing"""
    import pandas as pd
    import numpy as np
    return pd.DataFrame({
        'feature1': np.random.randn(100),
        'feature2': np.random.randn(100),
        'target': np.random.randint(0, 2, 100)
    })