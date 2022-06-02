FROM python:3.8.0

ARG MLFLOW_VERSION
RUN pip install \
    mlflow==$MLFLOW_VERSION \
    pymysql \
    boto3
RUN mkdir /mlflow/

EXPOSE 5000

## Environment variables made available through the Fargate task.
CMD mlflow server \
    --host 0.0.0.0 \
    --port 5000 \
    --default-artifact-root ${BUCKET} \
    --backend-store-uri mysql+pymysql://${USERNAME}:${PASSWORD}@${HOST}:${PORT}/${DATABASE}
