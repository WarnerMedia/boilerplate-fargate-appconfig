Feature: Health Check

    Scenario: Receive Successful Health Check Response
        Given that a service DNS record exists
        When we request the health check URL of the service
        Then we should receive a 200 response