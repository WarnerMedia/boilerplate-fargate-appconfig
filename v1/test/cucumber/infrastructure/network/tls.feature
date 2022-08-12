Feature: Secure Certificate Check

    Scenario: Receive Valid Secure Certificate TLS Response
        Given that a service DNS record exists
        When we request the health check URL using the "SSLv3_method" protocol
        Then we should get a "failure" response
        When we request the health check URL using the "TLSv1_method" protocol
        Then we should get a "failure" response
        When we request the health check URL using the "TLSv1_1_method" protocol
        Then we should get a "failure" response
        When we request the health check URL using the "TLSv1_2_method" protocol
        Then we should get a "successful" response