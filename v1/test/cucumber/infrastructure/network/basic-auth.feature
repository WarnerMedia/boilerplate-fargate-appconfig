Feature: Basic Authorization

    Scenario: Receive Basic Authorization Request
        Given that a service DNS record exists
        When we request the homepage of the service
        Then we should receive Basic Authorization response