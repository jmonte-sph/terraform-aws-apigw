resource "aws_api_gateway_rest_api" "api" {
  body = var.body_template

  name = var.name

  endpoint_configuration {
    types = var.types
  }
  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    {
      Name = var.name
    },
    var.tags
  )
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on  = [aws_api_gateway_rest_api_policy.policy_attachment]
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    redeployment = sha1(jsonencode([
      var.tf_resources_hash,
      aws_api_gateway_rest_api.api.body,
      var.enable_resource_policy ? var.resource_policy_json : null
      ]
    ))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "stage" {
  #checkov:skip=CKV2_AWS_51: Since its a community module, its up to the application's discretion.
  #checkov:skip=CKV_AWS_120:Caching should be optional as caching is disabled for some applications
  #checkov:skip=CKV2_AWS_29:Since apigw can be protected by Cloudfront
  #checkov:skip=CKV2_AWS_4:There is no loggging level defined for aws_api_gateway_stage. It is only available for aws_api_gateway_method_settings
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id

  stage_name            = var.stage
  variables             = length(var.vpc_links) > 0 ? merge({ for k, v in values(aws_api_gateway_vpc_link.vpc_link)[*] : v.name => v.id }, var.stage_variables) : var.stage_variables
  xray_tracing_enabled  = true
  cache_cluster_enabled = var.cache_cluster_enabled
  cache_cluster_size    = var.cache_cluster_size

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.log_group.arn
    format          = jsonencode(var.log_format)
  }

  depends_on = [aws_api_gateway_account.api_gateway_account]

  tags = var.tags

}

resource "aws_cloudwatch_log_group" "log_group" {
  #checkov:skip=CKV_AWS_338: Don't validate log retention days in shareable module
  #checkov:skip=CKV_AWS_158: Using default key in KMS instead of CMK
  #Custom name if it is imported
  name              = var.log_group_name != "" ? var.log_group_name : "${var.name}-access-logs"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.log_kms_key_id != "" ? var.log_kms_key_id : aws_kms_key.cloudwatch[0].arn

  tags = {
    Name = var.log_group_name != "" ? var.log_group_name : "${var.name}-access-logs"
  }

}

resource "aws_kms_key" "cloudwatch" {
  count = var.log_kms_key_id != "" ? 0 : 1

  description         = "Key for api gateway Cloudwatch log encryption"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.cloudwatch_logs_allow_apigw.json
}

resource "aws_api_gateway_method_settings" "method_settings" {
  #checkov:skip=CKV_AWS_225:Caching should be optional as caching is disabled for some applications
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.stage.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled        = var.metrics_enabled
    logging_level          = var.logging_level
    data_trace_enabled     = var.data_trace_enabled
    throttling_burst_limit = var.throttling_burst_limit
    throttling_rate_limit  = var.throttling_rate_limit
    cache_data_encrypted   = var.cache_data_encrypted
    caching_enabled        = var.caching_enabled
    cache_ttl_in_seconds   = var.cache_ttl
  }
}

resource "aws_api_gateway_vpc_link" "vpc_link" {
  for_each = var.vpc_links

  name        = each.key
  description = each.value.description
  target_arns = each.value.target_arns
}
