"""
Visitor Counter Lambda Function

This function is triggered by API Gateway when the frontend
JavaScript makes a GET request to /count.

Flow:
  1. Receive request from API Gateway
  2. Connect to DynamoDB
  3. Atomically increment the visit_count attribute
  4. Return the new count as JSON

"Atomically increment" means DynamoDB handles the read-and-update
as a single operation. Even if two visitors hit the site at the
exact same millisecond, each request gets its own increment —
no race condition, no lost counts. This is handled by
UpdateExpression with ADD, which is an atomic operation in DynamoDB.

Test update.
"""

import json
import os
import boto3

# Initialize the DynamoDB resource outside the handler function.
# Why outside? Lambda reuses the execution environment between
# invocations (called a "warm start"). By initializing the
# DynamoDB connection here, it's created once and reused across
# multiple requests — faster and cheaper.
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])


def handler(event, context):
    """
    Lambda entry point.

    Parameters:
        event   — the HTTP request details from API Gateway
                  (headers, query params, body, etc.)
        context — Lambda runtime info (function name, memory,
                  time remaining, etc.) — we don't need it here

    Returns:
        dict with statusCode and body — API Gateway converts
        this into an HTTP response to send back to the browser
    """

    try:
        # UpdateItem with ADD atomically increments visit_count by 1.
        # ReturnValues="UPDATED_NEW" tells DynamoDB to return the
        # value AFTER the increment, so we get the new count.
        response = table.update_item(
            Key={"id": "visitors"},
            UpdateExpression="ADD visit_count :inc",
            ExpressionAttributeValues={":inc": 1},
            ReturnValues="UPDATED_NEW",
        )

        # Extract the new count from the DynamoDB response.
        # Decimal is returned by boto3 — convert to int for JSON.
        visit_count = int(response["Attributes"]["visit_count"])

        return {
            "statusCode": 200,
            "body": json.dumps({"count": visit_count}),
        }

    except Exception as e:
        # Log the error to CloudWatch for debugging.
        # In production you'd use structured logging, but
        # print() works for Lambda — it writes to CloudWatch.
        print(f"Error: {e}")

        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Could not update visitor count"}),
        }
