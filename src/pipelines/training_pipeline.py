# src/pipelines/training_pipeline.py
from prefect import flow
from data.pipeline import data_pipeline_flow
from models.training import train_and_evaluate_models, register_model_in_registry
from monitoring.drift import setup_drift_monitoring
import mlflow


@flow(name="ml-training-pipeline", version="1.0")
def ml_training_pipeline():
    """End-to-end ML training pipeline"""
    logger = get_run_logger()

    try:
        # Execute data pipeline
        data_result = data_pipeline_flow()

        # Train and evaluate models
        training_result = train_and_evaluate_models(
            data_result["X_train"],
            data_result["X_test"],
            data_result["y_train"],
            data_result["y_test"],
            data_result["dataset_info"],
        )

        # Register best model
        if training_result["best_model"]:
            register_model_in_registry(
                training_result["best_model"],
                "breast-cancer-classifier",
                training_result["all_results"][training_result["best_model_name"]][
                    "metrics"
                ],
            )

        # Setup drift monitoring
        reference_data = data_result["X_train"].copy()
        reference_data["target"] = data_result["y_train"]
        setup_drift_monitoring(reference_data)

        logger.info("ML training pipeline completed successfully")

        return {
            "training_result": training_result,
            "data_info": data_result["dataset_info"],
        }

    except Exception as e:
        logger.error(f"ML training pipeline failed: {str(e)}")
        raise


if __name__ == "__main__":
    # Run the pipeline
    ml_training_pipeline()
