# src/optimization/resource_optimizer.py

import pandas as pd
import numpy as np
from typing import Dict, List, Optional
from datetime import datetime, timedelta
import asyncio
import logging
from kubernetes import client, config
from prometheus_client import Gauge, Counter

# Metrics
resource_optimization_actions = Counter(
    "resource_optimization_actions_total",
    "Total resource optimization actions",
    ["action_type"],
)
current_resource_utilization = Gauge(
    "current_resource_utilization_ratio",
    "Current resource utilization",
    ["resource_type", "namespace"],
)


class IntelligentResourceOptimizer:
    def __init__(self):
        self.logger = logging.getLogger(__name__)
        self.k8s_apps_v1 = client.AppsV1Api()
        self.k8s_autoscaling_v1 = client.AutoscalingV1Api()

        # Optimization thresholds
        self.cpu_scale_up_threshold = 0.7
        self.cpu_scale_down_threshold = 0.3
        self.memory_scale_up_threshold = 0.8
        self.memory_scale_down_threshold = 0.4
        self.request_scale_up_threshold = 100  # requests per second per pod
        self.request_scale_down_threshold = 20

    async def optimize_resources(self, namespace: str = "ml-platform"):
        """Main optimization loop"""
        try:
            self.logger.info(
                f"Starting resource optimization for namespace: {namespace}"
            )

            # Get current metrics
            metrics = await self._get_current_metrics(namespace)

            # Analyze and optimize each deployment
            deployments = self.k8s_apps_v1.list_namespaced_deployment(namespace)

            for deployment in deployments.items:
                await self._optimize_deployment(deployment, metrics, namespace)

            self.logger.info("Resource optimization completed")

        except Exception as e:
            self.logger.error(f"Resource optimization failed: {e}")

    async def _get_current_metrics(self, namespace: str) -> Dict:
        """Get current resource utilization metrics"""
        try:
            # This would query Prometheus for current metrics
            # For now, return mock data
            return {
                "cpu_utilization": 0.65,
                "memory_utilization": 0.75,
                "request_rate": 150,
                "cost_per_hour": 2.50,
            }
        except Exception as e:
            self.logger.error(f"Failed to get metrics: {e}")
            return {}

    async def _optimize_deployment(self, deployment, metrics: Dict, namespace: str):
        """Optimize a specific deployment"""
        deployment_name = deployment.metadata.name

        try:
            # Get current HPA
            hpa = self._get_hpa(deployment_name, namespace)

            # Analyze current state
            analysis = await self._analyze_deployment_state(deployment, hpa, metrics)

            # Determine optimization action
            action = await self._determine_optimization_action(
                analysis, deployment_name
            )

            if action:
                await self._execute_optimization_action(
                    action, deployment_name, namespace
                )

        except Exception as e:
            self.logger.error(f"Failed to optimize deployment {deployment_name}: {e}")

    async def _analyze_deployment_state(self, deployment, hpa, metrics: Dict) -> Dict:
        """Analyze current deployment state for optimization opportunities"""

        analysis = {
            "current_replicas": deployment.spec.replicas,
            "cpu_utilization": metrics.get("cpu_utilization", 0),
            "memory_utilization": metrics.get("memory_utilization", 0),
            "request_rate": metrics.get("request_rate", 0),
            "optimization_opportunities": [],
            "estimated_savings": 0,
        }

        # Check for over-provisioning
        if (
            analysis["cpu_utilization"] < self.cpu_scale_down_threshold
            and analysis["memory_utilization"] < self.memory_scale_down_threshold
            and analysis["request_rate"] < self.request_scale_down_threshold
        ):

            analysis["optimization_opportunities"].append(
                {
                    "type": "scale_down",
                    "reason": "Low resource utilization",
                    "current_replicas": analysis["current_replicas"],
                    "suggested_replicas": max(1, analysis["current_replicas"] - 1),
                    "estimated_savings": await self._calculate_savings(
                        analysis["current_replicas"] - 1
                    ),
                }
            )

        # Check for under-provisioning
        if (
            analysis["cpu_utilization"] > self.cpu_scale_up_threshold
            or analysis["memory_utilization"] > self.memory_scale_up_threshold
            or analysis["request_rate"] > self.request_scale_up_threshold
        ):

            analysis["optimization_opportunities"].append(
                {
                    "type": "scale_up",
                    "reason": "High resource utilization",
                    "current_replicas": analysis["current_replicas"],
                    "suggested_replicas": analysis["current_replicas"] + 1,
                    "estimated_savings": 0,  # Scale-up doesn't save money
                }
            )

        # Check resource requests/limits optimization
        resource_optimization = await self._analyze_resource_requests(deployment)
        if resource_optimization:
            analysis["optimization_opportunities"].extend(resource_optimization)

        return analysis

    async def _analyze_resource_requests(self, deployment) -> List[Dict]:
        """Analyze and optimize resource requests and limits"""
        optimizations = []

        for container in deployment.spec.template.spec.containers:
            resources = container.resources

            if resources and resources.requests:
                # Analyze CPU requests
                current_cpu = self._parse_cpu_request(
                    resources.requests.get("cpu", "100m")
                )
                suggested_cpu = await self._suggest_optimal_cpu(
                    container.name, deployment.metadata.name
                )

                if suggested_cpu and suggested_cpu < current_cpu:
                    optimizations.append(
                        {
                            "type": "reduce_cpu_request",
                            "container": container.name,
                            "current": f"{current_cpu * 1000:.0f}m",
                            "suggested": f"{suggested_cpu * 1000:.0f}m",
                            "estimated_savings": await self._calculate_cpu_savings(
                                current_cpu - suggested_cpu
                            ),
                        }
                    )

            if resources and resources.limits:
                # Analyze memory limits
                current_memory = self._parse_memory_request(
                    resources.limits.get("memory", "128Mi")
                )
                suggested_memory = await self._suggest_optimal_memory(
                    container.name, deployment.metadata.name
                )

                if suggested_memory and suggested_memory < current_memory:
                    optimizations.append(
                        {
                            "type": "reduce_memory_limit",
                            "container": container.name,
                            "current": f"{current_memory}Mi",
                            "suggested": f"{suggested_memory}Mi",
                            "estimated_savings": await self._calculate_memory_savings(
                                current_memory - suggested_memory
                            ),
                        }
                    )

        return optimizations

    async def _determine_optimization_action(
        self, analysis: Dict, deployment_name: str
    ) -> Optional[Dict]:
        """Determine the best optimization action to take"""
        if not analysis["optimization_opportunities"]:
            return None

        # Prioritize cost-saving actions
        cost_saving_actions = [
            op
            for op in analysis["optimization_opportunities"]
            if op["estimated_savings"] > 0
        ]

        if cost_saving_actions:
            # Take the action with highest savings
            best_action = max(cost_saving_actions, key=lambda x: x["estimated_savings"])
            self.logger.info(
                f"Selected optimization for {deployment_name}: {best_action['type']} "
                f"with estimated savings ${best_action['estimated_savings']:.2f}/hour"
            )
            return best_action

        # If no cost savings, consider performance actions
        performance_actions = [
            op
            for op in analysis["optimization_opportunities"]
            if op["estimated_savings"] == 0
        ]

        if performance_actions:
            best_action = performance_actions[0]  # Take first performance action
            self.logger.info(
                f"Selected performance optimization for {deployment_name}: {best_action['type']}"
            )
            return best_action

        return None

    async def _execute_optimization_action(
        self, action: Dict, deployment_name: str, namespace: str
    ):
        """Execute the optimization action"""
        try:
            if action["type"] == "scale_down":
                await self._scale_deployment(
                    deployment_name, namespace, action["suggested_replicas"]
                )
                resource_optimization_actions.labels(action_type="scale_down").inc()

            elif action["type"] == "scale_up":
                await self._scale_deployment(
                    deployment_name, namespace, action["suggested_replicas"]
                )
                resource_optimization_actions.labels(action_type="scale_up").inc()

            elif action["type"] in ["reduce_cpu_request", "reduce_memory_limit"]:
                await self._update_resource_requests(deployment_name, namespace, action)
                resource_optimization_actions.labels(
                    action_type="resource_optimization"
                ).inc()

            self.logger.info(
                f"Successfully executed {action['type']} for {deployment_name}"
            )

        except Exception as e:
            self.logger.error(
                f"Failed to execute optimization action for {deployment_name}: {e}"
            )

    # Helper methods for resource parsing and calculations
    def _parse_cpu_request(self, cpu_str: str) -> float:
        """Parse CPU request string to cores"""
        if cpu_str.endswith("m"):
            return int(cpu_str[:-1]) / 1000
        else:
            return float(cpu_str)

    def _parse_memory_request(self, memory_str: str) -> float:
        """Parse memory request string to megabytes"""
        if memory_str.endswith("Mi"):
            return float(memory_str[:-2])
        elif memory_str.endswith("Gi"):
            return float(memory_str[:-2]) * 1024
        else:
            return float(memory_str) / (1024 * 1024)  # Assume bytes

    async def _calculate_savings(self, replica_change: int) -> float:
        """Calculate estimated cost savings from replica change"""
        # This would use cloud provider pricing data
        # Simplified calculation: $0.10 per replica-hour
        return abs(replica_change) * 0.10

    async def _calculate_cpu_savings(self, cpu_cores: float) -> float:
        """Calculate savings from CPU reduction"""
        # Simplified: $0.02 per CPU-core-hour
        return cpu_cores * 0.02

    async def _calculate_memory_savings(self, memory_mb: float) -> float:
        """Calculate savings from memory reduction"""
        # Simplified: $0.01 per GB-hour
        return (memory_mb / 1024) * 0.01

    async def _suggest_optimal_cpu(
        self, container_name: str, deployment_name: str
    ) -> Optional[float]:
        """Suggest optimal CPU based on historical usage"""
        # This would analyze historical metrics to suggest optimal CPU
        # For now, return a fixed reduction
        return 0.1  # 100m

    async def _suggest_optimal_memory(
        self, container_name: str, deployment_name: str
    ) -> Optional[float]:
        """Suggest optimal memory based on historical usage"""
        # This would analyze historical metrics to suggest optimal memory
        return 128  # 128Mi

    # Kubernetes interaction methods
    def _get_hpa(self, deployment_name: str, namespace: str):
        """Get HorizontalPodAutoscaler for deployment"""
        try:
            return self.k8s_autoscaling_v1.read_namespaced_horizontal_pod_autoscaler(
                f"{deployment_name}-hpa", namespace
            )
        except client.exceptions.ApiException:
            return None

    async def _scale_deployment(
        self, deployment_name: str, namespace: str, replicas: int
    ):
        """Scale deployment to specified number of replicas"""
        patch = {"spec": {"replicas": replicas}}
        self.k8s_apps_v1.patch_namespaced_deployment(
            name=deployment_name, namespace=namespace, body=patch
        )

    async def _update_resource_requests(
        self, deployment_name: str, namespace: str, action: Dict
    ):
        """Update resource requests for a deployment"""
        deployment = self.k8s_apps_v1.read_namespaced_deployment(
            deployment_name, namespace
        )

        for container in deployment.spec.template.spec.containers:
            if container.name == action["container"]:
                if not container.resources:
                    container.resources = client.V1ResourceRequirements()

                if not container.resources.requests:
                    container.resources.requests = {}

                if action["type"] == "reduce_cpu_request":
                    container.resources.requests["cpu"] = action["suggested"]
                elif action["type"] == "reduce_memory_limit":
                    if not container.resources.limits:
                        container.resources.limits = {}
                    container.resources.limits["memory"] = action["suggested"]

        self.k8s_apps_v1.replace_namespaced_deployment(
            name=deployment_name, namespace=namespace, body=deployment
        )
