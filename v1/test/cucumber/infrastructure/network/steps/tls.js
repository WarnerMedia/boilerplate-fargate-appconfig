import assert from "assert";
import { Given, When, Then } from "@cucumber/cucumber";
import got from "got";
//import fs from 'fs';

When('we request the health check URL using the {string} protocol', async (protocol) => {
  const domain = process.env.SERVICE_DOMAIN;
  const hc = process.env.SERVICE_HEALTH_CHECK;
  const options = {
    timeout:10000,
    secureProtocol: protocol
  };
  try {
    this.response = await got.get("https://"+domain+hc,options);
    this.status = "successful";
  } catch (error) {
    console.error(error.name);
    this.status = "failure";
  }
});

Then('we should get a {string} response', (value) => {
  assert.strictEqual(this.status, value);
});