Feature: Main Security Scan

    Scenario: Scan Repository Code
        # Values for the "When" statement could be any combination of "negligible,low,medium,high,critical".
        When we run "high,critical" security scans on the repository
        # Values for the "Then" statement should be "pass" or "fail".
        Then we should "fail" if we receive any security violations