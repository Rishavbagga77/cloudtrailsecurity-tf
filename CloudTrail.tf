terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

#Creating Log Group 
resource "aws_cloudwatch_log_group" "cloudtrailloggingroup" {
  name = "cloudtrail-log-stream-${data.aws_caller_identity.current.account_id}"
}

#Creating Role policy for Role to be used in Trail to put and create logs in log group
resource "aws_iam_role_policy" "cloudtrail_log_rolepolicy" {
  name = "cloudtrail-policy"
  role = aws_iam_role.cloudtrail_log_role.id

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AWSCloudTrailCreateLogStream",
        "Effect" : "Allow",
        "Action" : ["logs:CreateLogStream"],
        "Resource" : ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${aws_cloudwatch_log_group.cloudtrailloggingroup.id}:*"
        ]
      },
      {
        "Sid" : "AWSCloudTrailPutLogEvent",
        "Effect" : "Allow",
        "Action" : ["logs:PutlogEvents"],
        "Resource" : ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${aws_cloudwatch_log_group.cloudtrailloggingroup.id}:*"
        ]
      }
    ]
  })
}

#Role to be attached with Trail
resource "aws_iam_role" "cloudtrail_log_role" {
  name = "cloudtrail-to-cloudwatch"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "cloudtrail.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

#Creating Trail
resource "aws_cloudtrail" "logging_trail" {
  name                          = "logging_trail-${data.aws_caller_identity.current.account_id}"
  s3_bucket_name                = aws_s3_bucket.trail.id
  s3_key_prefix                 = "cloudtrailkey"
  include_global_service_events = true
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrailloggingroup.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_log_role.arn
  depends_on                    = [aws_s3_bucket_policy.CloudtrailS3, aws_s3_bucket.trail]
}

#S3 bucket to Store Trail
resource "aws_s3_bucket" "trail" {
  bucket        = "cloudtraillogs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

#S3 bucket Policy to Store Trail
resource "aws_s3_bucket_policy" "CloudtrailS3" {
  bucket     = aws_s3_bucket.trail.id
  depends_on = [aws_s3_bucket.trail]
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AWSCloudTrailAclCheck",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "cloudtrail.amazonaws.com"
        },
        "Action" : "s3:GetBucketAcl",
        "Resource" : "${aws_s3_bucket.trail.arn}"
      },
      {
        "Sid" : "AWSCloudTrailWrite",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "cloudtrail.amazonaws.com"
        },
        "Action" : "s3:PutObject",
        "Resource" : "${aws_s3_bucket.trail.arn}/cloudtrailkey/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
        "Condition" : {
          "StringEquals" : {
            "s3:x-amz-acl" : "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

#creating SNS Topic
resource "aws_sns_topic" "cloudtrail_notifications" {
  name              = "Cloudtrail_Events"
  kms_master_key_id = "alias/aws/sns"
}
#creating SNS Subscription
resource "aws_sns_topic_subscription" "cloudtrail_notifications_sub" {
  topic_arn = aws_sns_topic.cloudtrail_notifications.arn
  protocol  = "email"
  endpoint  = "rishav@nclouds.com"
}

#creating metric Filters
resource "aws_cloudwatch_log_metric_filter" "AWSConsoleSignInFailure" {
  name           = "AWSConsoleSignInFailure"
  pattern        = "{ ($.eventName = ConsoleLogin) && ($.errorMessage = \"Failed authentication\") }"
  log_group_name = aws_cloudwatch_log_group.cloudtrailloggingroup.name

  metric_transformation {
    name          = "ConsoleSigninFailureCount"
    namespace     = "CloudTrailMetrics"
    value         = 1
    default_value = 0
    unit          = "Count"
  }
}
#creating Cloudwatch alarm
resource "aws_cloudwatch_metric_alarm" "AWSConsoleSignInFailureAlarm" {
  alarm_name          = "AWSConsoleSignInFailure-AccountID-${data.aws_caller_identity.current.account_id}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "ConsoleSigninFailureCount"
  namespace           = "CloudTrailMetrics"
  period              = 60
  statistic           = "Average"
  unit                = "Count"
  threshold           = 0
  alarm_description   = "P2 changes to NACL detected."
  alarm_actions       = [aws_sns_topic.cloudtrail_notifications.arn]
  treat_missing_data  = "notBreaching"
}
