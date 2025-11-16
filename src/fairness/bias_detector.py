# src/fairness/bias_detector.py

import pandas as pd
import numpy as np
from typing import Dict, List, Optional, Tuple
from sklearn.metrics import accuracy_score, precision_score, recall_score
from scipy import stats
import logging
from dataclasses import dataclass


@dataclass
class BiasReport:
    protected_attribute: str
    metric_disparities: Dict[str, float]
    statistical_tests: Dict[str, float]
    recommendations: List[str]
    severity: str  # low, medium, high


class BiasDetectionService:
    def __init__(self):
        self.logger = logging.getLogger(__name__)

    async def detect_bias(
        self,
        y_true: np.ndarray,
        y_pred: np.ndarray,
        protected_attributes: pd.DataFrame,
        privileged_groups: Dict[str, List],
    ) -> List[BiasReport]:
        """Detect bias across multiple protected attributes"""

        bias_reports = []

        for attr in protected_attributes.columns:
            report = await self._analyze_attribute_bias(
                y_true,
                y_pred,
                protected_attributes[attr],
                privileged_groups.get(attr, []),
            )
            bias_reports.append(report)

        return bias_reports

    async def _analyze_attribute_bias(
        self,
        y_true: np.ndarray,
        y_pred: np.ndarray,
        protected_attr: pd.Series,
        privileged_values: List,
    ) -> BiasReport:
        """Analyze bias for a single protected attribute"""

        # Calculate metrics for different groups
        groups = protected_attr.unique()
        metric_disparities = {}
        statistical_tests = {}

        for metric_name, metric_func in [
            ("accuracy", accuracy_score),
            ("precision", precision_score),
            ("recall", recall_score),
        ]:
            group_metrics = {}
            for group in groups:
                mask = protected_attr == group
                if mask.sum() > 0:  # Ensure group has samples
                    group_metrics[group] = metric_func(y_true[mask], y_pred[mask])

            # Calculate disparity
            if len(group_metrics) >= 2:
                min_metric = min(group_metrics.values())
                max_metric = max(group_metrics.values())
                disparity = (
                    (max_metric - min_metric) / max_metric if max_metric > 0 else 0
                )
                metric_disparities[metric_name] = disparity

        # Statistical tests
        try:
            # Chi-square test for independence
            contingency_table = pd.crosstab(protected_attr, y_pred)
            chi2, p_value, _, _ = stats.chi2_contingency(contingency_table)
            statistical_tests["chi2_p_value"] = p_value

            # T-test for score differences between groups
            if len(groups) == 2:
                group1_mask = protected_attr == groups[0]
                group2_mask = protected_attr == groups[1]

                if (
                    group1_mask.sum() > 10 and group2_mask.sum() > 10
                ):  # Ensure sufficient samples
                    t_stat, t_p_value = stats.ttest_ind(
                        y_pred[group1_mask], y_pred[group2_mask]
                    )
                    statistical_tests["t_test_p_value"] = t_p_value
        except Exception as e:
            self.logger.warning(f"Statistical tests failed: {e}")

        # Generate recommendations
        recommendations = self._generate_bias_recommendations(
            metric_disparities, statistical_tests
        )

        # Determine severity
        severity = self._determine_severity(metric_disparities, statistical_tests)

        return BiasReport(
            protected_attribute=protected_attr.name,
            metric_disparities=metric_disparities,
            statistical_tests=statistical_tests,
            recommendations=recommendations,
            severity=severity,
        )

    def _generate_bias_recommendations(
        self, metric_disparities: Dict[str, float], statistical_tests: Dict[str, float]
    ) -> List[str]:
        """Generate bias mitigation recommendations"""
        recommendations = []

        # Check metric disparities
        for metric, disparity in metric_disparities.items():
            if disparity > 0.1:
                recommendations.append(
                    f"High {metric} disparity ({disparity:.2%}) detected. "
                    f"Consider re-sampling or re-weighting training data."
                )
            elif disparity > 0.05:
                recommendations.append(
                    f"Moderate {metric} disparity ({disparity:.2%}) detected. "
                    f"Monitor closely and consider fairness constraints."
                )

        # Check statistical significance
        if statistical_tests.get("chi2_p_value", 1) < 0.05:
            recommendations.append(
                "Statistically significant association between protected attribute and predictions. "
                "Consider bias mitigation techniques."
            )

        if not recommendations:
            recommendations.append("No significant bias detected. Continue monitoring.")

        return recommendations

    def _determine_severity(
        self, metric_disparities: Dict[str, float], statistical_tests: Dict[str, float]
    ) -> str:
        """Determine bias severity level"""

        # Check for high disparities
        high_disparities = any(
            disparity > 0.1 for disparity in metric_disparities.values()
        )
        significant_stats = statistical_tests.get("chi2_p_value", 1) < 0.01

        if high_disparities and significant_stats:
            return "high"
        elif any(disparity > 0.05 for disparity in metric_disparities.values()):
            return "medium"
        else:
            return "low"
