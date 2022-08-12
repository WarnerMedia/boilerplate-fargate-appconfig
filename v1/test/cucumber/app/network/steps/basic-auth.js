const assert = require('assert');
const { When, Then } = require('cucumber');
const got = require('got');

When('we request the homepage of {string}', async (url) => {
  const options = {
    timeout:10000
  };
  try {
    this.response = await got.get(url,options);
    this.statusCode = this.response.statusCode;
  } catch (error) {
    if (error.response) {
      this.statusCode = error.response.statusCode;
    } else {
      console.error(error.code);
      this.statusCode = 408;
    }
  }
});

Then('we should receive Basic Authorization response', () => {
  assert.equal(this.statusCode, 401);
});