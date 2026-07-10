#!/usr/bin/env python3
"""
Cloud Operations Lab - Operational Event Logger (Python)

Writes a custom operational event record to the DynamoDB ops-logs table.
Run directly on the instance via SSM Session Manager.

Prerequisites (run once on the instance):
    pip3 install boto3

Usage:
    export TABLE_NAME=cloud-ops-lab-dev-ops-logs
    python3 log_event.py --event-type "deployment" --message "Patched kernel to 6.1.x"
"""

import argparse
import os
import time
import urllib.request
from datetime import datetime, timezone

import boto3


def get_imds_token() -> str:
    req = urllib.request.Request(
        "http://169.254.169.254/latest/api/token",
        method="PUT",
        headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"},
    )
    with urllib.request.urlopen(req, timeout=2) as resp:
        return resp.read().decode()


def get_metadata(token: str, path: str) -> str:
    req = urllib.request.Request(
        f"http://169.254.169.254/latest/meta-data/{path}",
        headers={"X-aws-ec2-metadata-token": token},
    )
    with urllib.request.urlopen(req, timeout=2) as resp:
        return resp.read().decode()


def main() -> None:
    parser = argparse.ArgumentParser(description="Write an operational event to DynamoDB")
    parser.add_argument("--event-type", default="manual_event", help="Operational event type")
    parser.add_argument("--message", default="Operational log entry", help="Event message")
    parser.add_argument("--table-name", default=None, help="DynamoDB table name (overrides TABLE_NAME env var)")
    args = parser.parse_args()

    table_name = args.table_name or os.environ.get("TABLE_NAME")
    if not table_name:
        raise SystemExit("ERROR: provide --table-name or set the TABLE_NAME environment variable.")

    token = get_imds_token()
    instance_id = get_metadata(token, "instance-id")
    region = get_metadata(token, "placement/region")

    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    ttl = int(time.time()) + 2592000  # 30 days

    item = {
        "instance_id": {"S": instance_id},
        "log_timestamp": {"S": timestamp},
        "event_type": {"S": args.event_type},
        "message": {"S": args.message},
        "ttl": {"N": str(ttl)},
    }

    client = boto3.client("dynamodb", region_name=region)
    client.put_item(TableName=table_name, Item=item)

    print(f"Event logged: [{args.event_type}] {args.message}")
    print(f"Instance: {instance_id} | Table: {table_name} | Timestamp: {timestamp}")


if __name__ == "__main__":
    main()
