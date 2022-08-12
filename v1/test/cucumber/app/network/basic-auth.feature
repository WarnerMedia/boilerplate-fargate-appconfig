Feature: Basic Authorization

    Scenario: Receive Basic Authorization Request
        When we request the homepage of "http://localhost:8080/"
        Then we should receive Basic Authorization response