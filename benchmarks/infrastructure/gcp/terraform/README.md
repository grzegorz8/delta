# Create infrastructure with Terraform

1. Install [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli?in=terraform/gcp-get-started).

2. Create and download [service account key](https://cloud.google.com/iam/docs/creating-managing-service-account-keys#iam-service-account-keys-create-console).
   The path to the file is required in the next step (`credentials_file`).

3. Create Terraform variable file `benchmarks/infrastructure/gcp/terraform/terraform.tfvars` and fill in variable values.
    ```tf
    project          = "<PROJECT_ID>"
    region           = "<REGION>"
    zone             = "<ZONE>"
    credentials_file = "<CREDENTIALS_FILE>"
    bucket_name      = "<BUCKET_NAME>"
    dataproc_workers = WORKERS_COUNT
    ```
   Please check `variables.tf` to learn more about each parameter.

4. Run:
    ```bash
    terraform init
    terraform validate
    terraform apply
    ```

5. Once the benchmarks are finished, destroy the resources. The command below deletes Dataproc Metastore, 
   Dataproc cluster, but **it preserves Google Storage bucket**.
    ```bash
    terraform destroy
    ```
