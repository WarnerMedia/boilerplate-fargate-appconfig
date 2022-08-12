Feature: Certificate Check

    Scenario: Receive Authorized Secure Certificate Response
        Given that a service DNS record exists
        When we request the health check URL and receive the certificate response
        Then we should get an authorized response