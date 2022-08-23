Feature: Secure Certificate Check

    Scenario: Receive Valid Secure Certificate TLS Response
        Given that a service DNS record exists
        When we request the health check URL using the "SSLv3" protocol
        Then we should get a "failure" response
        When we request the health check URL using the "TLSv1" protocol
        Then we should get a "failure" response
        When we request the health check URL using the "TLSv1.1" protocol
        Then we should get a "failure" response
        When we request the health check URL using the "TLSv1.2" protocol
        Then we should get a "successful" response
        When we request the health check URL using the "TLSv1.3" protocol
        Then we should get a "successful" response