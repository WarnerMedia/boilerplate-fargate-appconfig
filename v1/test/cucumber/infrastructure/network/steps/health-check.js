import assert from "assert";
import { Given, When, Then } from "@cucumber/cucumber";
import got from "got";

let global = {};

When('we request the health check URL of the service', async () => {
  const domain = process.env.SERVICE_DOMAIN;
  const hc = process.env.SERVICE_HEALTH_CHECK;
  const options = {
    timeout:{
      request:10000
    }
  };
  try {
    global.response = await got.get("https://"+domain+hc,options);
    global.statusCode = global.response.statusCode;
  } catch (error) {
    if (error.response) {
      global.statusCode = error.response.statusCode;
    } else {
      console.error(error.name);
      global.statusCode = 408;
    }
  }
});

Then('we should receive a {int} response', (code) => {
  assert.equal(global.statusCode, code);
});