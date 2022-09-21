Feature: Check for "HTTP/2" Protocol

    Scenario: Receive Response Via "HTTP/2" Protocol
        Given that a service DNS record exists
        When we connect via the "HTTP/2" protocol
        Then we should not receive a connection error