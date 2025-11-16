# src/monitoring/dashboard.py
import streamlit as st
import pandas as pd
import numpy as np
import plotly.graph_objects as go
import plotly.express as px
from plotly.subplots import make_subplots
import mlflow
from datetime import datetime, timedelta
import requests
import json
import sys
import os

# Add src to path
sys.path.append(os.path.join(os.path.dirname(__file__), ".."))


class MLMonitoringDashboard:
    """Enterprise ML Monitoring Dashboard"""

    def __init__(self):
        self.mlflow_client = mlflow.tracking.MlflowClient()
        self.setup_page()

    def setup_page(self):
        """Configure Streamlit page"""
        st.set_page_config(
            page_title="MLOps Monitoring Dashboard",
            page_icon="📊",
            layout="wide",
            initial_sidebar_state="expanded",
        )

        st.title("🚀 MLOps Production Monitoring Dashboard")
        st.markdown(
            """
        Real-time monitoring of model performance, data drift, and system health
        """
        )

    def run(self):
        """Run the dashboard"""

        # Sidebar for navigation
        st.sidebar.title("Navigation")
        page = st.sidebar.selectbox(
            "Choose a page",
            ["Model Performance", "Data Drift", "System Health", "Alert History"],
        )

        # Display selected page
        if page == "Model Performance":
            self.show_model_performance()
        elif page == "Data Drift":
            self.show_data_drift()
        elif page == "System Health":
            self.show_system_health()
        elif page == "Alert History":
            self.show_alert_history()

    def show_model_performance(self):
        """Display model performance metrics"""

        st.header("📈 Model Performance Monitoring")

        # Model metrics
        col1, col2, col3, col4 = st.columns(4)

        with col1:
            st.metric("Current Model Version", "v1.2.3")

        with col2:
            st.metric("Production Accuracy", "95.2%", "0.8%")

        with col3:
            st.metric("Inference Latency", "45ms", "-5ms")

        with col4:
            st.metric("Total Predictions", "12,458", "342")

        # Performance charts
        col1, col2 = st.columns(2)

        with col1:
            st.subheader("Accuracy Over Time")
            self.plot_accuracy_trend()

        with col2:
            st.subheader("Feature Importance")
            self.plot_feature_importance()

        # Recent predictions table
        st.subheader("Recent Predictions")
        self.show_recent_predictions()

    def show_data_drift(self):
        """Display data drift monitoring"""

        st.header("🔍 Data Drift Detection")

        # Drift status
        col1, col2, col3 = st.columns(3)

        with col1:
            status_color = "🟢"  # Green
            st.metric("Overall Drift Status", "Stable", delta="No significant drift")

        with col2:
            st.metric("Features with Drift", "2/30", "2 features")

        with col3:
            st.metric("Last Drift Check", "5 minutes ago")

        # Drift visualization
        col1, col2 = st.columns(2)

        with col1:
            st.subheader("Feature Distribution Drift")
            self.plot_feature_drift()

        with col2:
            st.subheader("Drift Severity by Feature")
            self.plot_drift_severity()

        # Drift details
        st.subheader("Drift Analysis Details")
        self.show_drift_details()

    def show_system_health(self):
        """Display system health metrics"""

        st.header("⚙️ System Health Monitoring")

        # System metrics
        col1, col2, col3, col4 = st.columns(4)

        with col1:
            st.metric("API Status", "Healthy", "Operational")

        with col2:
            st.metric("Model Loading", "Success", "All models loaded")

        with col3:
            st.metric("Database Connection", "Stable", "No issues")

        with col4:
            st.metric("Memory Usage", "68%", "2%")

        # Resource monitoring
        st.subheader("Resource Utilization")
        col1, col2 = st.columns(2)

        with col1:
            self.plot_cpu_memory_usage()

        with col2:
            self.plot_request_volume()

    def show_alert_history(self):
        """Display alert history"""

        st.header("🚨 Alert History")

        # Alert statistics
        col1, col2, col3 = st.columns(3)

        with col1:
            st.metric("Total Alerts", "24")

        with col2:
            st.metric("Critical Alerts", "3")

        with col3:
            st.metric("Resolved", "21")

        # Alert timeline
        st.subheader("Alert Timeline")
        self.plot_alert_timeline()

        # Recent alerts table
        st.subheader("Recent Alerts")
        self.show_recent_alerts()

    def plot_accuracy_trend(self):
        """Plot accuracy trend over time"""
        # Simulated data - in production, fetch from MLflow or database
        dates = pd.date_range(start="2024-01-01", periods=30, freq="D")
        accuracy = np.random.normal(0.95, 0.02, 30).cumsum() / np.arange(1, 31)

        fig = go.Figure()
        fig.add_trace(
            go.Scatter(
                x=dates,
                y=accuracy,
                mode="lines+markers",
                name="Accuracy",
                line=dict(color="#1f77b4", width=3),
            )
        )

        fig.update_layout(
            title="Model Accuracy Over Time",
            xaxis_title="Date",
            yaxis_title="Accuracy",
            template="plotly_white",
        )

        st.plotly_chart(fig, use_container_width=True)

    def plot_feature_importance(self):
        """Plot feature importance"""
        # Simulated feature importance
        features = [
            "worst radius",
            "mean perimeter",
            "worst area",
            "mean concave points",
            "worst concavity",
        ]
        importance = [0.25, 0.18, 0.15, 0.12, 0.08]

        fig = go.Figure(
            go.Bar(x=importance, y=features, orientation="h", marker_color="#2ecc71")
        )

        fig.update_layout(
            title="Top Feature Importance",
            xaxis_title="Importance",
            yaxis_title="Features",
            template="plotly_white",
        )

        st.plotly_chart(fig, use_container_width=True)

    def plot_feature_drift(self):
        """Plot feature distribution drift"""
        # Simulated drift data
        feature_names = ["mean radius", "mean texture", "worst radius"]
        reference_dist = np.random.normal(15, 3, 1000)
        current_dist = np.random.normal(16, 3.5, 1000)  # Slight drift

        fig = go.Figure()
        fig.add_trace(
            go.Histogram(x=reference_dist, name="Reference", opacity=0.7, nbinsx=30)
        )
        fig.add_trace(
            go.Histogram(x=current_dist, name="Current", opacity=0.7, nbinsx=30)
        )

        fig.update_layout(
            title="Feature Distribution: Mean Radius",
            xaxis_title="Value",
            yaxis_title="Frequency",
            template="plotly_white",
            barmode="overlay",
        )

        st.plotly_chart(fig, use_container_width=True)

    def plot_drift_severity(self):
        """Plot drift severity by feature"""
        features = [f"Feature {i}" for i in range(1, 11)]
        drift_scores = np.random.uniform(0, 0.5, 10)

        colors = [
            "green" if score < 0.1 else "orange" if score < 0.3 else "red"
            for score in drift_scores
        ]

        fig = go.Figure(
            go.Bar(x=drift_scores, y=features, orientation="h", marker_color=colors)
        )

        fig.update_layout(
            title="Drift Severity by Feature",
            xaxis_title="Drift Score",
            yaxis_title="Features",
            template="plotly_white",
        )

        st.plotly_chart(fig, use_container_width=True)

    def show_drift_details(self):
        """Display detailed drift analysis"""
        drift_data = {
            "Feature": ["mean radius", "mean texture", "worst area", "mean perimeter"],
            "Drift Score": [0.45, 0.12, 0.08, 0.03],
            "Status": ["High Drift", "Medium Drift", "Low Drift", "No Drift"],
            "P-Value": [0.001, 0.045, 0.210, 0.650],
        }

        df = pd.DataFrame(drift_data)
        st.dataframe(df, use_container_width=True)

    def plot_cpu_memory_usage(self):
        """Plot CPU and memory usage"""
        time_points = list(range(24))
        cpu_usage = np.random.normal(45, 10, 24)
        memory_usage = np.random.normal(65, 8, 24)

        fig = make_subplots(specs=[[{"secondary_y": False}]])

        fig.add_trace(
            go.Scatter(
                x=time_points,
                y=cpu_usage,
                name="CPU Usage (%)",
                line=dict(color="#e74c3c", width=3),
            )
        )

        fig.add_trace(
            go.Scatter(
                x=time_points,
                y=memory_usage,
                name="Memory Usage (%)",
                line=dict(color="#3498db", width=3),
            )
        )

        fig.update_layout(
            title="Resource Utilization (24h)",
            xaxis_title="Hour",
            yaxis_title="Usage (%)",
            template="plotly_white",
        )

        st.plotly_chart(fig, use_container_width=True)

    def plot_request_volume(self):
        """Plot request volume over time"""
        hours = list(range(24))
        requests = np.random.poisson(50, 24) + np.sin(np.array(hours) * 0.5) * 20

        fig = go.Figure(
            go.Bar(
                x=hours, y=requests, marker_color="#9b59b6", name="Requests per Hour"
            )
        )

        fig.update_layout(
            title="Request Volume (24h)",
            xaxis_title="Hour of Day",
            yaxis_title="Number of Requests",
            template="plotly_white",
        )

        st.plotly_chart(fig, use_container_width=True)

    def plot_alert_timeline(self):
        """Plot alert timeline"""
        alert_data = {
            "timestamp": pd.date_range("2024-01-01", periods=10, freq="3D"),
            "severity": [
                "High",
                "Medium",
                "Low",
                "High",
                "Medium",
                "Low",
                "Medium",
                "High",
                "Low",
                "Medium",
            ],
            "type": [
                "Data Drift",
                "Performance",
                "System",
                "Data Drift",
                "System",
                "Performance",
                "Data Drift",
                "System",
                "Performance",
                "Data Drift",
            ],
        }

        df = pd.DataFrame(alert_data)

        fig = px.scatter(
            df,
            x="timestamp",
            y="severity",
            color="type",
            size=[10, 8, 6, 10, 8, 6, 8, 10, 6, 8],
            title="Alert Timeline by Severity and Type",
        )

        st.plotly_chart(fig, use_container_width=True)

    def show_recent_alerts(self):
        """Display recent alerts table"""
        alert_data = {
            "Timestamp": ["2024-01-15 14:30", "2024-01-15 10:15", "2024-01-14 16:45"],
            "Type": ["Data Drift", "Performance Degradation", "System Health"],
            "Severity": ["High", "Medium", "Low"],
            "Status": ["Investigating", "Resolved", "Resolved"],
            "Description": [
                "Significant drift in feature distributions",
                "Accuracy dropped by 5%",
                "High memory usage detected",
            ],
        }

        df = pd.DataFrame(alert_data)
        st.dataframe(df, use_container_width=True)

    def show_recent_predictions(self):
        """Display recent predictions table"""
        prediction_data = {
            "Timestamp": [
                "2024-01-15 14:25:12",
                "2024-01-15 14:25:10",
                "2024-01-15 14:25:08",
            ],
            "Prediction": [1, 0, 1],
            "Confidence": [0.92, 0.87, 0.95],
            "Drift Detected": [False, True, False],
            "Response Time (ms)": [42, 38, 45],
        }

        df = pd.DataFrame(prediction_data)
        st.dataframe(df, use_container_width=True)


def main():
    """Main function to run the dashboard"""
    dashboard = MLMonitoringDashboard()
    dashboard.run()


if __name__ == "__main__":
    main()
