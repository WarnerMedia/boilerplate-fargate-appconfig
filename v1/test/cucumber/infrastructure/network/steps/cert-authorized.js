import assert from "assert";
import { Given, When, Then } from "@cucumber/cucumber";
import got from "got";
//import fs from 'fs';

let global = {};

When('we request the health check URL and receive the certificate response', async () => {
  const domain = process.env.SERVICE_DOMAIN;
  const hc = process.env.SERVICE_HEALTH_CHECK;
  const options = {
    timeout:{
      request:10000
    }
  };
  try {
    global.response = await got.get("https://"+domain+hc,options);
    global.authorized = global.response.socket.authorized;
  } catch (error) {
    console.error(error.name);
    global.authorized = false;
  }
});

Then('we should get an authorized response', () => {
  assert.strictEqual(global.authorized, true);
});