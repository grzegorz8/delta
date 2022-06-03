#!/usr/bin/env bash
docker build -t databricks/mlflow:1.26.1 --build-arg MLFLOW_VERSION=1.26.1 .
