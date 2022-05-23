# Create infrastructure with Terraform

1. Install [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli?in=terraform/aws-get-started).
2. Ensure that your AWS CLI is configured. You should either have valid credentials in shared credentials file (e.g. `~/.aws/credentials`)
   or export keys as environment variables:
   ```bash
   export AWS_ACCESS_KEY_ID="anaccesskey"
   export AWS_SECRET_ACCESS_KEY="asecretkey"
   ```

3. Create Terraform variable file `benchmarks/infrastructure/aws/terraform/terraform.tfvars` and fill in variable values.
    ```tf
    benchmarks_bucket_name = "<BUCKET_NAME>"
    user_ip_address        = "<MY_IP>"
    emr_workers            = WORKERS_COUNT
    emr_public_key_path    = "<PUBLIC_KEY_PATH>"
    tags                   = {
      key1 = "value1"
      key2 = "value2"
    }
    ```
   Please check `variables.tf` to learn more about each parameter.

4. Run:
    ```bash
    terraform init
    terraform validate
    terraform apply
    ```
   As a result, a new VPC, S3 bucket MySQL instance (metastore) and EMR cluster will be created.
   The `apply` command returns master node public address that will be used when running benchmarks.
   ```
   Apply complete! Resources: 16 added, 0 changed, 0 destroyed.
   Outputs:
   master_node_address = "35.165.163.250"
   ```

5. Once the benchmarks are finished, destroy the resources.
    ```bash
    terraform destroy
    ```
