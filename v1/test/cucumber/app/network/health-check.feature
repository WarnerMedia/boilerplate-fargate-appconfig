Feature: Health Check

    Scenario: Receive Successful Health Check Response
        When we request the health check route: "http://localhost:8080/hc/"
        Then we should receive a 200 response