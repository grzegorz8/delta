# Create infrastructure with Terraform

1. Install [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli?in=terraform/aws-get-started).
2. Ensure that your AWS CLI is configured. You should either have valid credentials in shared credentials file (e.g. `~/.aws/credentials`)
   ```
   [default]
   aws_access_key_id = anaccesskey
   aws_secret_access_key = asecretkey
   ```
   or export keys as environment variables:
   ```bash
   export AWS_ACCESS_KEY_ID="anaccesskey"
   export AWS_SECRET_ACCESS_KEY="asecretkey"
   ```

3. Create Terraform variable file `benchmarks/infrastructure/aws/terraform/terraform.tfvars` and fill in variable values.
   ```tf
   region                 = "<REGION>"
   availability_zone1     = "<AVAILABILITY_ZONE1>"
   availability_zone2     = "<AVAILABILITY_ZONE2>"
   benchmarks_bucket_name = "<BUCKET_NAME>"
   source_bucket_name     = "<SOURCE_BUCKET_NAME>"
   mysql_user             = "<MYSQL_USER>"
   mysql_password         = "<MYSQL_PASSWORD>"
   emr_public_key_path    = "<EMR_PUBLIC_KEY_PATH>"
   user_ip_address        = "<MY_IP>"
   emr_workers            = WORKERS_COUNT
   emr_public_key_path    = "<PUBLIC_KEY_PATH>"
   tags                   = {
     key1 = "value1"
     key2 = "value2"
   }
   ```
   Please check `variables.tf` to learn more about each parameter.

4. Initialize terraform. Run:
   ```bash
   terraform init
   terraform validate
   ```

5. Then create ECR repository. Run:
   ```bash
   terraform apply -target=module.ecr
   ```
   ```
   Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

   Outputs:

   mlflow_repository_url = "781336771001.dkr.ecr.us-west-2.amazonaws.com/mlflow"
   ```

6. Build and push MLflow docker image. Go to `benchmarks/infrastructure/docker/mlflow` directory and run:
   ```bash
   ./release-to-aws-ecr.sh <account-id> <region> mlflow
   ```

7. Run:
   ```bash
   terraform apply
   ```
   As a result, an EMR cluster and MLflow service is created.
   The `apply` command returns `master_node_address` that will be used when running benchmarks.
   ```
   Apply complete! Resources: 46 added, 0 changed, 0 destroyed.

   Outputs:

   master_node_address = "34.219.132.75"
   mlflow_address = "http://mlflow-alb-1730686932.us-west-2.elb.amazonaws.com:5000"
   mlflow_repository_url = "<account-id>.dkr.ecr.us-west-2.amazonaws.com/mlflow"
   ```

8. Once the benchmarks are finished, destroy the resources.
   ```bash
   terraform destroy
   ```
   If the S3 bucket contains any objects, it will not be destroyed automatically.
   One need to do that manually to avoid any accidental data loss.
   ```
   Error: deleting S3 Bucket (my-bucket): BucketNotEmpty: The bucket you tried to delete is not empty 
   status code: 409, request id: Q11TYZ5E0B23QGQ2, host id: WdeFY88km5IBhy+bi2hqXzgjBxjrn1+OPtCstsWDjkwGNCyEhXYjq330DZq1jbfNXojBEejH6Wg=
   ```
   It is worth mentioning, that you can destroy only a part of the infrastructure by specifying targets:
   ```bash
   terraform destroy -auto-approve -target=module.processing
   ```
