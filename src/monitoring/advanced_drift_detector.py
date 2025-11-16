# src/monitoring/drift/advanced_drift_detector.py

import numpy as np
import pandas as pd
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
from scipy import stats
from sklearn.ensemble import IsolationForest
from sklearn.covariance import EllipticEnvelope
import warnings

warnings.filterwarnings("ignore")


@dataclass
class DriftResult:
    drift_detected: bool
    drift_score: float
    drift_type: str
    features_affected: List[str]
    confidence: float
    metadata: Dict


class MultiModalDriftDetector:
    """Advanced drift detection using multiple statistical tests and ML methods"""

    def __init__(self, config: Dict):
        self.config = config
        self.detectors = {
            "ks_test": self._ks_test_drift,
            "psi": self._psi_drift,
            "mmd": self._mmd_drift,
            "isolation_forest": self._isolation_forest_drift,
            "covariance_drift": self._covariance_drift,
            "classifier_drift": self._classifier_drift,
        }

    def detect_drift(
        self,
        reference_data: pd.DataFrame,
        current_data: pd.DataFrame,
        target_column: Optional[str] = None,
    ) -> DriftResult:
        """Detect drift using ensemble of methods"""

        results = {}

        # Statistical drift detection
        results["ks_test"] = self._ks_test_drift(reference_data, current_data)
        results["psi"] = self._psi_drift(reference_data, current_data)
        results["mmd"] = self._mmd_drift(reference_data, current_data)

        # ML-based drift detection
        results["isolation_forest"] = self._isolation_forest_drift(
            reference_data, current_data
        )
        results["covariance_drift"] = self._covariance_drift(
            reference_data, current_data
        )

        if target_column:
            results["classifier_drift"] = self._classifier_drift(
                reference_data, current_data, target_column
            )

        # Ensemble decision
        return self._ensemble_detection(results, reference_data, current_data)

    def _ks_test_drift(self, reference: pd.DataFrame, current: pd.DataFrame) -> Dict:
        """Kolmogorov-Smirnov test for feature distribution drift"""
        drift_scores = {}
        p_values = {}

        for column in reference.columns:
            if reference[column].dtype in ["float64", "int64"]:
                stat, p_value = stats.ks_2samp(
                    reference[column].dropna(), current[column].dropna()
                )
                drift_scores[column] = stat
                p_values[column] = p_value

        overall_drift = any(p < 0.05 for p in p_values.values())
        overall_score = max(drift_scores.values()) if drift_scores else 0

        return {
            "drift_detected": overall_drift,
            "drift_score": overall_score,
            "p_values": p_values,
            "method": "ks_test",
        }

    def _psi_drift(self, reference: pd.DataFrame, current: pd.DataFrame) -> Dict:
        """Population Stability Index for feature drift"""
        psi_scores = {}

        for column in reference.columns:
            if reference[column].dtype in ["float64", "int64"]:
                # Create bins based on reference data
                bins = np.histogram_bin_edges(reference[column].dropna(), bins=10)

                # Calculate frequencies
                ref_freq, _ = np.histogram(reference[column].dropna(), bins=bins)
                curr_freq, _ = np.histogram(current[column].dropna(), bins=bins)

                # Avoid division by zero
                ref_freq = ref_freq + 0.0001
                curr_freq = curr_freq + 0.0001

                # Calculate PSI
                psi = np.sum((curr_freq - ref_freq) * np.log(curr_freq / ref_freq))
                psi_scores[column] = psi

        # PSI interpretation: < 0.1: no drift, 0.1-0.25: moderate, > 0.25: significant
        significant_drift = any(psi > 0.1 for psi in psi_scores.values())
        overall_score = max(psi_scores.values()) if psi_scores else 0

        return {
            "drift_detected": significant_drift,
            "drift_score": overall_score,
            "psi_scores": psi_scores,
            "method": "psi",
        }

    def _mmd_drift(self, reference: pd.DataFrame, current: pd.DataFrame) -> Dict:
        """Maximum Mean Discrepancy for distribution drift"""
        try:
            from sklearn.gaussian_process.kernels import RBF
            from sklearn.metrics.pairwise import pairwise_kernels

            # Sample data for computational efficiency
            ref_sample = reference.sample(min(1000, len(reference)), random_state=42)
            curr_sample = current.sample(min(1000, len(current)), random_state=42)

            # Calculate MMD
            kernel = RBF(length_scale=1.0)
            K_ref = pairwise_kernels(ref_sample, ref_sample, metric=kernel)
            K_curr = pairwise_kernels(curr_sample, curr_sample, metric=kernel)
            K_cross = pairwise_kernels(ref_sample, curr_sample, metric=kernel)

            mmd = K_ref.mean() + K_curr.mean() - 2 * K_cross.mean()

            return {
                "drift_detected": mmd > 0.05,  # Threshold can be tuned
                "drift_score": mmd,
                "method": "mmd",
            }
        except ImportError:
            return {
                "drift_detected": False,
                "drift_score": 0.0,
                "method": "mmd",
                "error": "scikit-learn not available",
            }

    def _isolation_forest_drift(
        self, reference: pd.DataFrame, current: pd.DataFrame
    ) -> Dict:
        """Isolation Forest for anomaly-based drift detection"""
        # Train on reference data
        clf = IsolationForest(contamination=0.1, random_state=42)
        clf.fit(reference)

        # Predict on current data
        anomalies = clf.predict(current)
        anomaly_ratio = (anomalies == -1).mean()

        return {
            "drift_detected": anomaly_ratio > 0.15,  # More than 15% anomalies
            "drift_score": anomaly_ratio,
            "method": "isolation_forest",
        }

    def _covariance_drift(self, reference: pd.DataFrame, current: pd.DataFrame) -> Dict:
        """Covariance-based drift detection"""
        try:
            # Fit elliptic envelope on reference data
            envelope = EllipticEnvelope(contamination=0.1, random_state=42)
            envelope.fit(reference)

            # Predict on current data
            outliers = envelope.predict(current)
            outlier_ratio = (outliers == -1).mean()

            return {
                "drift_detected": outlier_ratio > 0.2,
                "drift_score": outlier_ratio,
                "method": "covariance_drift",
            }
        except Exception as e:
            return {
                "drift_detected": False,
                "drift_score": 0.0,
                "method": "covariance_drift",
                "error": str(e),
            }

    def _classifier_drift(
        self, reference: pd.DataFrame, current: pd.DataFrame, target_column: str
    ) -> Dict:
        """Classifier-based drift detection"""
        try:
            from sklearn.ensemble import RandomForestClassifier
            from sklearn.model_selection import cross_val_score

            # Prepare data
            X_ref = reference.drop(columns=[target_column])
            y_ref = np.zeros(len(X_ref))  # Label reference as 0

            X_curr = current.drop(columns=[target_column])
            y_curr = np.ones(len(X_curr))  # Label current as 1

            # Combine and shuffle
            X_combined = pd.concat([X_ref, X_curr], ignore_index=True)
            y_combined = np.concatenate([y_ref, y_curr])

            # Train classifier to distinguish between reference and current
            clf = RandomForestClassifier(n_estimators=50, random_state=42)
            scores = cross_val_score(
                clf, X_combined, y_combined, cv=5, scoring="roc_auc"
            )

            # High AUC means classifier can distinguish -> drift detected
            mean_auc = scores.mean()

            return {
                "drift_detected": mean_auc > 0.7,  # AUC > 0.7 indicates good separation
                "drift_score": mean_auc,
                "method": "classifier_drift",
            }
        except Exception as e:
            return {
                "drift_detected": False,
                "drift_score": 0.0,
                "method": "classifier_drift",
                "error": str(e),
            }

    def _ensemble_detection(
        self, results: Dict, reference: pd.DataFrame, current: pd.DataFrame
    ) -> DriftResult:
        """Combine results from multiple detectors"""

        # Weighted voting based on method reliability
        weights = {
            "ks_test": 0.2,
            "psi": 0.25,
            "mmd": 0.2,
            "isolation_forest": 0.15,
            "covariance_drift": 0.1,
            "classifier_drift": 0.1,
        }

        total_weight = 0
        weighted_score = 0
        drift_votes = 0

        features_affected = set()

        for method, result in results.items():
            if result.get("drift_detected", False):
                drift_votes += weights.get(method, 0.1)

            # Aggregate drift scores
            if "drift_score" in result:
                weighted_score += result["drift_score"] * weights.get(method, 0.1)
                total_weight += weights.get(method, 0.1)

            # Collect affected features
            if "psi_scores" in result:
                high_psi_features = [
                    f for f, score in result["psi_scores"].items() if score > 0.1
                ]
                features_affected.update(high_psi_features)

        # Normalize scores
        ensemble_score = weighted_score / total_weight if total_weight > 0 else 0
        ensemble_drift = drift_votes > 0.5  # Majority vote

        # Determine drift type
        drift_type = self._determine_drift_type(results, reference, current)

        return DriftResult(
            drift_detected=ensemble_drift,
            drift_score=ensemble_score,
            drift_type=drift_type,
            features_affected=list(features_affected),
            confidence=min(ensemble_score, 1.0),
            metadata={"individual_results": results},
        )

    def _determine_drift_type(
        self, results: Dict, reference: pd.DataFrame, current: pd.DataFrame
    ) -> str:
        """Determine the type of drift detected"""

        # Check for covariate shift (feature distribution change)
        covariate_drift = any(
            results[method]["drift_detected"]
            for method in ["ks_test", "psi", "mmd"]
            if method in results
        )

        # Check for concept drift (relationship change)
        concept_drift = results.get("classifier_drift", {}).get("drift_detected", False)

        if covariate_drift and concept_drift:
            return "covariate_and_concept_drift"
        elif covariate_drift:
            return "covariate_drift"
        elif concept_drift:
            return "concept_drift"
        else:
            return "no_drift"
