import assert from "assert";
import { Given, When, Then } from "@cucumber/cucumber";
import got from "got";
//import fs from 'fs';

When('we request the health check URL and receive the certificate response', async () => {
  const domain = process.env.SERVICE_DOMAIN;
  const hc = process.env.SERVICE_HEALTH_CHECK;
  const options = {
    timeout:10000
  };
  try {
    this.response = await got.get("https://"+domain+hc,options);
    this.authorized = this.response.socket.authorized;
  } catch (error) {
    console.error(error.name);
    this.authorized = false;
  }
});

Then('we should get an authorized response', () => {
  assert.strictEqual(this.authorized, true);
});