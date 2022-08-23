import assert from "assert";
import { Given, When, Then } from "@cucumber/cucumber";
import dns from "dns";

//Set global variables.
var records = [];

Given('that a service DNS record exists', (done) => {
  const domain = process.env.SERVICE_DOMAIN;
  dns.resolve(domain, 'ANY', function (error, list) {
    if (error) {
      console.error(error.code);
      done(error);
    } else {
      done();
    }
  });
});

When('we check for a DNS entry using an Internet Protocol Version {int} {string} record type', (version,type,done) => {
  const domain = process.env.SERVICE_DOMAIN;
  dns.resolve(domain, type, function (error, list) {
    if (error) {
      records = [];
      console.error(error.code);
      done(error);
    } else {
      records = list;
      done();
    }
  });
});

Then('the DNS record should be found', function () {
  assert.notDeepStrictEqual(records.length,0);
});