Feature: Domain Name System Entries

    Scenario: Retrieve IPv4 DNS Record
        Given that a service DNS record exists
        When we check for a DNS entry using an Internet Protocol Version 4 "A" record type
        Then the DNS record should be found

    # Scenario: Retrieve IPv6 DNS Record
    #     Given that a service DNS record exists
    #     When we check for a DNS entry using an Internet Protocol Version 6 "AAAA" record type
    #     Then the DNS record should be found