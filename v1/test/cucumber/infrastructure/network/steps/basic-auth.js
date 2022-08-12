const assert = require('assert');
const { Given, When, Then } = require('cucumber');
const got = require('got');

When('we request the homepage of the service', async () => {
  const domain = process.env.SERVICE_DOMAIN;
  const options = {
    timeout:10000
  };
  try {
    this.response = await got.get("https://"+domain,options);
    this.statusCode = this.response.statusCode;
  } catch (error) {
    if (error.response) {
      this.statusCode = error.response.statusCode;
    } else {
      console.error(error.name);
      this.statusCode = 408;
    }
  }
});

Then('we should receive Basic Authorization response', () => {
  assert.equal(this.statusCode, 401);
});