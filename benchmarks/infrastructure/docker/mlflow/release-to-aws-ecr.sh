#!/usr/bin/env bash

ACCOUNT_ID=$1
REGION=$2
REPOSITORY=$3
MLFLOW_VERSION=${4:-1.26.1}
TAG=${MLFLOW_VERSION}

ECR_URL=${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_URL}

REPOSITORY=${REPOSITORY}

docker build . -t ${REPOSITORY}:${TAG} --build-arg MLFLOW_VERSION=${MLFLOW_VERSION}

docker tag ${REPOSITORY}:${TAG} ${ECR_URL}/${REPOSITORY}:${TAG}
docker tag ${REPOSITORY}:${TAG} ${ECR_URL}/${REPOSITORY}:latest
docker push ${ECR_URL}/${REPOSITORY}:${TAG}
docker push ${ECR_URL}/${REPOSITORY}:latest
