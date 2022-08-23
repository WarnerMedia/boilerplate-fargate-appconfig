import assert from "assert";
import { Given, When, Then } from "@cucumber/cucumber";
import got from "got";
//import fs from 'fs';

let global = {};

When('we request the health check URL using Internet Protocol Version {int} and receive a response', async (version) => {
  const domain = process.env.SERVICE_DOMAIN;
  const hc = process.env.SERVICE_HEALTH_CHECK;
  const options = {
    timeout:{
      request:10000
    },
    family: version
  };
  try {
    global.response = await got.get("https://"+domain+hc,options);
    global.status = "successful";
  } catch (error) {
    console.error(error);
    global.status = "failure";
  }
});

Then('we should get a {string} Internet Protocol Version {int} response', (status,version) => {
  assert.equal(global.status, status);
});