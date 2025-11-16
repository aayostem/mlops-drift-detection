# src/monitoring/drift.py
import pandas as pd
import numpy as np
from evidently import ColumnMapping
from evidently.report import Report
from evidently.metrics import *
from evidently.metric_preset import DataDriftPreset, TargetDriftPreset
from evidently.test_suite import TestSuite
from evidently.tests import *
from prefect import task, flow
import mlflow
import json
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
import logging

logger = logging.getLogger(__name__)


class DriftDetector:
    """Comprehensive drift detection system"""

    def __init__(self, reference_data: pd.DataFrame):
        self.reference_data = reference_data
        self.column_mapping = ColumnMapping(
            target="target",
            prediction="prediction",
            numerical_features=[
                col for col in reference_data.columns if col != "target"
            ],
            datetime=None,
        )

    def detect_data_drift(self, current_data: pd.DataFrame) -> Dict:
        """Detect data drift between reference and current data"""

        # Data Drift Report
        data_drift_report = Report(
            metrics=[
                DataDriftPreset(),
            ]
        )

        data_drift_report.run(
            reference_data=self.reference_data,
            current_data=current_data,
            column_mapping=self.column_mapping,
        )

        # Data Quality Report
        data_quality_report = Report(
            metrics=[
                DatasetSummaryMetric(),
                ColumnSummaryMetric(column_name="mean radius"),
                ColumnSummaryMetric(column_name="mean texture"),
                DatasetMissingValuesMetric(),
                DatasetCorrelationsMetric(),
            ]
        )

        data_quality_report.run(
            reference_data=self.reference_data,
            current_data=current_data,
            column_mapping=self.column_mapping,
        )

        # Data Drift Tests
        data_drift_test_suite = TestSuite(
            tests=[
                TestNumberOfDriftedFeatures(),
                TestShareOfDriftedFeatures(),
                TestFeatureValueDrift(column_name="mean radius"),
                TestFeatureValueDrift(column_name="mean texture"),
                TestAllFeaturesValueDrift(),
            ]
        )

        data_drift_test_suite.run(
            reference_data=self.reference_data,
            current_data=current_data,
            column_mapping=self.column_mapping,
        )

        # Combine results
        drift_results = {
            "timestamp": datetime.utcnow().isoformat(),
            "data_drift": data_drift_report.as_dict(),
            "data_quality": data_quality_report.as_dict(),
            "drift_tests": data_drift_test_suite.as_dict(),
            "summary": self._generate_drift_summary(
                data_drift_report.as_dict(), data_drift_test_suite.as_dict()
            ),
        }

        # Log to MLflow
        self._log_drift_to_mlflow(drift_results)

        return drift_results

    def _generate_drift_summary(self, drift_report: Dict, drift_tests: Dict) -> Dict:
        """Generate a summary of drift detection results"""

        # Extract drift percentage
        drift_metrics = drift_report["metrics"]
        drift_percentage = None

        for metric in drift_metrics:
            if metric["metric"] == "DatasetDriftMetric":
                drift_percentage = metric["result"]["drift_share"]
                break

        # Extract test results
        test_results = drift_tests["tests"]
        failed_tests = []

        for test in test_results:
            if not test["status"] == "SUCCESS":
                failed_tests.append(
                    {
                        "name": test["name"],
                        "description": test["description"],
                        "status": test["status"],
                    }
                )

        # Determine overall drift status
        overall_status = "NO_DRIFT"
        if drift_percentage and drift_percentage > 0.2:  # 20% threshold
            overall_status = "HIGH_DRIFT"
        elif drift_percentage and drift_percentage > 0.1:  # 10% threshold
            overall_status = "MEDIUM_DRIFT"
        elif failed_tests:
            overall_status = "QUALITY_ISSUES"

        return {
            "overall_status": overall_status,
            "drift_percentage": drift_percentage,
            "failed_tests_count": len(failed_tests),
            "failed_tests": failed_tests,
            "alert_required": overall_status in ["HIGH_DRIFT", "MEDIUM_DRIFT"],
        }

    def _log_drift_to_mlflow(self, drift_results: Dict):
        """Log drift detection results to MLflow"""

        try:
            with mlflow.start_run(run_name="drift_detection", nested=True):
                # Log drift metrics
                mlflow.log_metrics(
                    {
                        "drift_percentage": drift_results["summary"]["drift_percentage"]
                        or 0,
                        "failed_tests_count": drift_results["summary"][
                            "failed_tests_count"
                        ],
                        "alert_required": int(
                            drift_results["summary"]["alert_required"]
                        ),
                    }
                )

                # Log drift report as artifact
                mlflow.log_dict(
                    drift_results,
                    f"drift_report_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.json",
                )

                # Log overall status as tag
                mlflow.set_tag(
                    "drift_status", drift_results["summary"]["overall_status"]
                )

        except Exception as e:
            logger.error(f"Failed to log drift results to MLflow: {str(e)}")


@task
def monitor_production_drift(
    reference_data: pd.DataFrame, current_data: pd.DataFrame
) -> Dict:
    """Monitor drift in production data"""

    detector = DriftDetector(reference_data)
    drift_results = detector.detect_data_drift(current_data)

    # Trigger alert if needed
    if drift_results["summary"]["alert_required"]:
        trigger_drift_alert(drift_results)

    return drift_results


@task
def trigger_drift_alert(drift_results: Dict):
    """Trigger alerts for significant drift"""

    alert_message = f"""
    🚨 MODEL DRIFT DETECTED 🚨
    
    Time: {drift_results['timestamp']}
    Status: {drift_results['summary']['overall_status']}
    Drift Percentage: {drift_results['summary']['drift_percentage']:.2%}
    Failed Tests: {drift_results['summary']['failed_tests_count']}
    
    Required Action: Investigate data quality and consider model retraining.
    """

    logger.warning(alert_message)

    # In production, you would integrate with:
    # - Slack/Teams webhooks
    # - Email notifications
    # - PagerDuty for critical alerts
    # - ServiceNow for incident management


@flow(name="drift-monitoring-pipeline")
def drift_monitoring_flow():
    """Scheduled drift monitoring pipeline"""

    logger.info("Starting drift monitoring pipeline")

    try:
        # Load reference data (from training)
        reference_data = load_reference_data()

        # Load current production data (simulated)
        current_data = simulate_production_data()

        # Monitor for drift
        drift_results = monitor_production_drift(reference_data, current_data)

        logger.info(
            f"Drift monitoring completed: {drift_results['summary']['overall_status']}"
        )

        return drift_results

    except Exception as e:
        logger.error(f"Drift monitoring pipeline failed: {str(e)}")
        raise


def load_reference_data() -> pd.DataFrame:
    """Load reference dataset used for training"""
    # In production, this would load from your feature store or database
    from sklearn.datasets import load_breast_cancer

    data = load_breast_cancer()
    df = pd.DataFrame(data.data, columns=data.feature_names)
    df["target"] = data.target
    return df


def simulate_production_data() -> pd.DataFrame:
    """Simulate current production data with some drift"""
    from sklearn.datasets import load_breast_cancer

    data = load_breast_cancer()
    df = pd.DataFrame(data.data, columns=data.feature_names)

    # Introduce some drift by modifying feature distributions
    np.random.seed(42)
    drift_mask = np.random.choice([0, 1], size=len(df), p=[0.7, 0.3])

    # Apply drift to a subset of data
    for col in ["mean radius", "mean texture", "worst radius"]:
        df.loc[drift_mask == 1, col] *= 1.2  # Increase values by 20%

    df["target"] = data.target
    return df
