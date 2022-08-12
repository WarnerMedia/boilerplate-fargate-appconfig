const assert = require('assert');
const { Given, When, Then } = require('cucumber');
const got = require('got');
const fs = require('fs');

When('we request the health check URL using Internet Protocol Version {int} and receive a response', async (version) => {
  const domain = process.env.SERVICE_DOMAIN;
  const hc = process.env.SERVICE_HEALTH_CHECK;
  const options = {
    timeout:10000,
    family: version
  };
  try {
    this.response = await got.get("https://"+domain+hc,options);
    this.status = "successful";
  } catch (error) {
    console.error(error);
    this.status = "failure";
  }
});

Then('we should get a {string} Internet Protocol Version {int} response', (status,version) => {
  assert.equal(this.status, status);
});