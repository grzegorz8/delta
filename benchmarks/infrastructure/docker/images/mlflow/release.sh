#!/bin/bash
ACCOUNT_ID=781336771001
REGION=us-west-2
REPOSITORY=mlflow-repository
MLFLOW_VERSION=1.26.1
TAG=${MLFLOW_VERSION}

ECR_URL=${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_URL}

REPOSITORY=${REPOSITORY}

docker build . -t ${REPOSITORY}:${TAG} \
  --build-arg  MLFLOW_VERSION=${MLFLOW_VERSION}

docker tag ${REPOSITORY}:${TAG} ${ECR_URL}/${REPOSITORY}:${TAG}
docker push ${ECR_URL}/${REPOSITORY}:${TAG}
