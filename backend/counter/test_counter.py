"""
Unit Tests for Visitor Counter Lambda Function

These tests verify the Lambda function works correctly WITHOUT
hitting real AWS services. We use "moto" — a library that mocks
AWS services in memory. When the Lambda function calls DynamoDB,
it's actually talking to a fake DynamoDB running locally in the
test process.

Why mock instead of testing against real AWS?
  - Speed: tests run in milliseconds, not seconds
  - Cost: no AWS charges for test runs
  - Isolation: tests don't affect production data
  - Reliability: no network dependency, no flaky tests
  - Safety: can't accidentally corrupt real counter

Test structure follows the Arrange-Act-Assert pattern:
  1. Arrange — set up the mock environment and test data
  2. Act — call the function being tested
  3. Assert — verify the result is what we expected
"""

import json
import boto3
import pytest
from moto import mock_aws


# ────────────────────────────────────────────────────────────
# FIXTURES
# ────────────────────────────────────────────────────────────
# Pytest fixtures are setup functions that run before each test.
# They create the environment the test needs, then clean it up
# automatically after the test finishes.
#
# @pytest.fixture is a decorator — it tells pytest "this
# function provides test infrastructure, not a test itself."
# ────────────────────────────────────────────────────────────

@pytest.fixture
def aws_environment(monkeypatch):
    """
    Creates a mock AWS environment with a DynamoDB table
    seeded with an initial counter value of 0.

    The 'with mock_aws()' context manager intercepts all
    boto3 calls and routes them to moto's in-memory fakes.
    Nothing hits real AWS.
    """
    with mock_aws():
        # Set the environment variables the Lambda function reads.
        # AWS_DEFAULT_REGION is needed because the Lambda function
        # initializes boto3 at module level without specifying a
        # region. On AWS, Lambda sets this automatically. In the
        # test environment, we have to set it ourselves.
        monkeypatch.setenv("TABLE_NAME", "cloud-resume-counter")
        monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")

        # Create the mock DynamoDB table (same schema as Terraform)
        dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
        table = dynamodb.create_table(
            TableName="cloud-resume-counter",
            KeySchema=[
                {"AttributeName": "id", "KeyType": "HASH"}
            ],
            AttributeDefinitions=[
                {"AttributeName": "id", "AttributeType": "S"}
            ],
            BillingMode="PAY_PER_REQUEST",
        )

        # Seed the table with the initial counter item
        table.put_item(Item={"id": "visitors", "visit_count": 0})

        # We need to reimport the Lambda function INSIDE the mock
        # context so it connects to the fake DynamoDB, not real AWS.
        # importlib.reload re-executes the module, which re-runs
        # the top-level boto3 connection code.
        import importlib
        import lambda_function
        importlib.reload(lambda_function)

        yield lambda_function, table


# ────────────────────────────────────────────────────────────
# TESTS
# ────────────────────────────────────────────────────────────

class TestVisitorCounter:
    """Tests for the visitor counter Lambda function."""

    def test_first_visit_returns_count_of_one(self, aws_environment):
        """
        First call should increment from 0 to 1.
        Verifies the basic increment logic works.
        """
        lambda_function, _ = aws_environment

        # Act — call the handler with an empty event
        # (our function doesn't use the event or context)
        result = lambda_function.handler({}, None)

        # Assert
        body = json.loads(result["body"])
        assert result["statusCode"] == 200
        assert body["count"] == 1

    def test_multiple_visits_increment_correctly(self, aws_environment):
        """
        Multiple calls should increment sequentially.
        Verifies the counter doesn't reset between calls.
        """
        lambda_function, _ = aws_environment

        # Act — call the handler 5 times
        for i in range(5):
            result = lambda_function.handler({}, None)

        # Assert — after 5 calls, count should be 5
        body = json.loads(result["body"])
        assert result["statusCode"] == 200
        assert body["count"] == 5

    def test_response_format_is_valid_json(self, aws_environment):
        """
        API Gateway expects a specific response format:
          { "statusCode": int, "body": "JSON string" }
        Verifies the Lambda returns this structure.
        """
        lambda_function, _ = aws_environment

        result = lambda_function.handler({}, None)

        # Assert — response has required keys
        assert "statusCode" in result
        assert "body" in result

        # Assert — body is valid JSON with a "count" key
        body = json.loads(result["body"])
        assert "count" in body
        assert isinstance(body["count"], int)

    def test_counter_persists_across_calls(self, aws_environment):
        """
        Verifies the counter value is actually stored in DynamoDB,
        not just returned from memory. We call the function, then
        read DynamoDB directly to confirm the value matches.
        """
        lambda_function, table = aws_environment

        # Act — increment 3 times via the function
        for _ in range(3):
            lambda_function.handler({}, None)

        # Read directly from the mock DynamoDB table
        response = table.get_item(Key={"id": "visitors"})
        stored_count = int(response["Item"]["visit_count"])

        # Assert — DynamoDB value matches what the function returned
        assert stored_count == 3

    def test_counter_returns_positive_integer(self, aws_environment):
        """
        Verifies the count is always a positive integer.
        Guards against edge cases like negative counts or floats.
        """
        lambda_function, _ = aws_environment

        result = lambda_function.handler({}, None)
        body = json.loads(result["body"])

        assert body["count"] > 0
        assert isinstance(body["count"], int)


    def test_missing_counter_is_created(self, aws_environment):
        lambda_function, table = aws_environment
        table.delete_item(Key={"id": "visitors"})

        result = lambda_function.handler({}, None)

        assert result["statusCode"] == 200
        assert json.loads(result["body"]) == {"count": 1}
        assert table.get_item(Key={"id": "visitors"})["Item"]["visit_count"] == 1

    def test_database_failure_returns_generic_error(self, aws_environment, monkeypatch):
        from botocore.exceptions import ClientError

        lambda_function, _ = aws_environment

        def fail_update(**kwargs):
            raise ClientError(
                {"Error": {"Code": "AccessDeniedException", "Message": "private resource details"}},
                "UpdateItem",
            )

        monkeypatch.setattr(lambda_function.table, "update_item", fail_update)
        result = lambda_function.handler({}, None)

        assert result["statusCode"] == 500
        assert json.loads(result["body"]) == {"error": "Could not update visitor count"}
        assert "private resource details" not in result["body"]
