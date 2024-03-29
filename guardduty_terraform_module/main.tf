data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_iam_policy_document" "guardduty_bucket" {
  statement {
    sid = "Allow PutObject"
    actions = [
      "s3:PutObject"
    ]

    resources = [
      "${aws_s3_bucket.guardduty.arn}/*"
    ]

    principals {
      type        = "Service"
      identifiers = ["guardduty.amazonaws.com"]
    }
  }

  statement {
    sid = "Allow GetBucketLocation"
    actions = [
      "s3:GetBucketLocation"
    ]

    resources = [
      aws_s3_bucket.guardduty.arn
    ]

    principals {
      type        = "Service"
      identifiers = ["guardduty.amazonaws.com"]
    }
  }
}

resource "aws_s3_bucket" "guardduty" {
  bucket        = var.bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_policy" "gd_bucket_policy" {
  bucket = aws_s3_bucket.guardduty.id
  policy = data.aws_iam_policy_document.guardduty_bucket.json
}

data "aws_iam_policy_document" "guardduty_kms" {
  statement {
    sid = "Allow GuardDuty to encrypt findings"
    actions = [
      "kms:GenerateDataKey"
    ]

    resources = [
      "arn:aws:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:key/*"
    ]

    principals {
      type        = "Service"
      identifiers = ["guardduty.amazonaws.com"]
    }
  }

  statement {
    sid = "Allow root user to modify/delete key"
    actions = [
      "kms:*"
    ]

    resources = [
      "arn:aws:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:key/*"
    ]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "guardduty_key" {
  description             = "Encryption key for Guardduty findings"
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.guardduty_kms.json
}

resource "aws_kms_alias" "guardduty_key" {
  name          = "alias/guardduty-kms"
  target_key_id = aws_kms_key.guardduty_key.key_id
}

resource "aws_guardduty_detector" "mmg_guardduty" {
  enable = true
  finding_publishing_frequency = "FIFTEEN_MINUTES" # default SIX_HOURS
}

# GuardDuty EKS Runtime Monitoring is managed as part of the new "Runtime Monitoring" feature.
resource "aws_guardduty_detector_feature" "runtime_monitoring" {
  detector_id = aws_guardduty_detector.mmg_guardduty.id
  name        = "RUNTIME_MONITORING"
  status      = "ENABLED"

  additional_configuration {
    name   = "EKS_ADDON_MANAGEMENT"
    status = "ENABLED"
  }  

  additional_configuration {
    name   = "ECS_FARGATE_AGENT_MANAGEMENT"
    status = "ENABLED"
  }

}


resource "aws_guardduty_detector_feature" "disable_lambda_network_logs_monitoring" {
  detector_id = aws_guardduty_detector.mmg_guardduty.id
  name        = "LAMBDA_NETWORK_LOGS"
  status      = "DISABLED"
}


resource "aws_guardduty_detector_feature" "disable_ebs_malware_protection_monitoring" {
  detector_id = aws_guardduty_detector.mmg_guardduty.id
  name        = "EBS_MALWARE_PROTECTION"
  status      = "DISABLED"
}


resource "aws_guardduty_detector_feature" "disable_rds_login_events_monitoring" {
  detector_id = aws_guardduty_detector.mmg_guardduty.id
  name        = "RDS_LOGIN_EVENTS"
  status      = "DISABLED"
}

resource "aws_guardduty_detector_feature" "disable_s3_data_events_monitoring" {
  detector_id = aws_guardduty_detector.mmg_guardduty.id
  name        = "S3_DATA_EVENTS"
  status      = "DISABLED"
}


resource "aws_guardduty_publishing_destination" "findings_bucket" {
  destination_arn = aws_s3_bucket.guardduty.arn
  detector_id     = aws_guardduty_detector.mmg_guardduty.id
  kms_key_arn     = aws_kms_key.guardduty_key.arn


  depends_on = [aws_s3_bucket_policy.gd_bucket_policy]

}