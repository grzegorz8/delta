data "aws_caller_identity" "current" {}

locals {
  accountId = data.aws_caller_identity.current.account_id
}
