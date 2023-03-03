# Copyright (c) 2023 Snowflake Inc.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

# 	http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

// Storage integration in SF
resource "snowflake_storage_integration" "this" {
  provider = snowflake

  name                      = "AWS_VPC_FLOW_STORAGE_INTEGRATION_${local.suffix}"
  type                      = "EXTERNAL_STAGE"
  enabled                   = true
  storage_allowed_locations = ["s3://${var.bucket_name}/${var.prefix}"]
  storage_provider          = "S3"
  storage_aws_role_arn      = "arn:aws:iam::${local.account_id}:role/${local.s3_reader_role_name}"
}

// SF external stage
resource "snowflake_stage" "this" {
  name                = local.snowflake_stage
  url                 = "s3://${var.bucket_name}/${var.prefix}"
  database            = var.database
  schema              = var.schema
  storage_integration = snowflake_storage_integration.this.name
}

// Table
resource "snowflake_table" "this" {
  database = var.database
  schema   = var.schema
  name     = var.table

  column {
    name     = "record"
    type     = "VARIANT"
    nullable = true
  }
}

// Wait for IAM role to be created
resource "time_sleep" "wait_for_role" {
  depends_on      = [aws_iam_role_policy.s3_reader]
  create_duration = "30s"
}

// Pipe
resource "snowflake_pipe" "this" {
  database       = var.database
  schema         = var.schema
  name           = "AWS_VPC_FLOW_PIPE_${local.suffix}"
  copy_statement = "copy into \"${var.database}\".\"${var.schema}\".\"${var.table}\" from @${var.database}.${var.schema}.${local.snowflake_stage} file_format = (type = parquet);"
  auto_ingest    = true
  depends_on = [
    snowflake_table.this,
    snowflake_stage.this,
    time_sleep.wait_for_role
  ]
}

// View
resource "snowflake_view" "this" {
  database = var.database
  schema   = var.schema
  name     = var.view

  statement = <<-SQL
  select 
    "record":account_id::varchar(16) as account_id,
    "record":action::varchar(16) as action,
    "record":bytes::integer as bytes,
    "record":dstaddr::varchar(128) as dstaddr,
    "record":dstport::integer as dstport,
    "record":end::TIMESTAMP as "END",
    "record":interface_id::varchar(32) as interface_id,
    "record":log_status::varchar(8) as log_status,
    "record":packets::integer as packets,
    "record":protocol::integer as protocol,
    "record":srcaddr::varchar(128) as srcaddr,
    "record":srcport::integer as srcport,
    "record":start::TIMESTAMP as "START",
    "record":version::varchar(8) as version
  from "${var.database}"."${var.schema}"."${var.table}";
SQL

  depends_on = [
    snowflake_table.this
  ]

}
