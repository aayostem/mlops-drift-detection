# opa/policies/model-deployment.rego

package kubernetes.validating.model_deployment

import data.kubernetes.admission

deny[msg] {
    input.request.kind.kind == "ModelDeployment"
    input.request.operation == "CREATE"
    
    # Require model version
    not input.request.object.spec.modelVersion
    msg := "ModelDeployment must specify modelVersion"
}

deny[msg] {
    input.request.kind.kind == "ModelDeployment"
    input.request.operation == "CREATE"
    
    # Validate model registry
    not startswith(input.request.object.spec.modelUri, "models:/")
    msg := "ModelDeployment modelUri must use MLflow model registry format"
}

deny[msg] {
    input.request.kind.kind == "Deployment"
    input.request.operation == "CREATE"
    input.request.object.metadata.labels.app == "ml-model-api"
    
    # Require resource limits
    not input.request.object.spec.template.spec.containers[_].resources.limits
    msg := "ML model API deployments must have resource limits"
}

deny[msg] {
    input.request.kind.kind == "Deployment"
    input.request.operation == "CREATE"
    input.request.object.metadata.labels.app == "ml-model-api"
    
    # Validate security context
    not input.request.object.spec.template.spec.securityContext.runAsNonRoot
    msg := "ML model API must run as non-root user"
}

# Allow only approved base images
deny[msg] {
    input.request.kind.kind == "Deployment"
    input.request.operation == "CREATE"
    
    image := input.request.object.spec.template.spec.containers[_].image
    not startswith(image, "123456789.dkr.ecr.us-west-2.amazonaws.com/")
    msg := sprintf("Image %v must come from approved ECR registry", [image])
}