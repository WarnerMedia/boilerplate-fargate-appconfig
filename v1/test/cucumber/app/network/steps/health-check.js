import assert from "assert";
import { When, Then } from "@cucumber/cucumber";
import got from "got";

let global = {};

When('we request the health check route: {string}', async (url) => {
  const options = {
    timeout:{
      request:10000
    }
  };
  try {
    global.response = await got.get(url,options);
    global.statusCode = global.response.statusCode;
  } catch (error) {
    if (error.response) {
      global.statusCode = error.response.statusCode;
    } else {
      console.error(error.code);
      global.statusCode = 408;
    }
  }
});

Then('we should receive a {int} response', (code) => {
  assert.equal(global.statusCode, code);
});