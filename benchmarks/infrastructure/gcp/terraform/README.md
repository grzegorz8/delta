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
   As a result, a new Google Storage bucket, a Dataproc Metastore and a Dataproc cluster will be created.
   The `apply` command returns master node public address that will be used when running benchmarks.
   ```
   Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
   Outputs:
   master_node_address = "35.165.163.250"
   ```

5. Once the benchmarks are finished, destroy the resources. If the Google Storage bucket contains any objects, it will
   not be destroyed automatically. One need to do that manually to avoid any accidental data loss.
    ```bash
    terraform destroy
    ```
