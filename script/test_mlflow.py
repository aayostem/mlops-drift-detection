# scripts/test_mlflow.py
import mlflow
import mlflow.sklearn
from sklearn.ensemble import RandomForestClassifier
from sklearn.datasets import load_iris
from sklearn.model_selection import train_test_split


def test_mlflow_connection():
    """Test MLflow connection and basic functionality"""
    try:
        # Test connection
        mlflow.set_tracking_uri("http://localhost:5000")
        mlflow.set_experiment("test-experiment")

        # Load data
        iris = load_iris()
        X_train, X_test, y_train, y_test = train_test_split(iris.data, iris.target)

        # Log a simple model
        with mlflow.start_run():
            model = RandomForestClassifier()
            model.fit(X_train, y_train)

            # Log parameters and metrics
            mlflow.log_param("n_estimators", 100)
            mlflow.log_metric("accuracy", model.score(X_test, y_test))

            # Log model
            mlflow.sklearn.log_model(model, "model")

        print("✅ MLflow test successful! Check http://localhost:5000")

    except Exception as e:
        print(f"❌ MLflow test failed: {e}")


if __name__ == "__main__":
    test_mlflow_connection()
