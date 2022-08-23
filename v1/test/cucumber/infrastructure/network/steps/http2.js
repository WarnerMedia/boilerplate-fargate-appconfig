import assert from "assert";
import { Given, When, Then } from "@cucumber/cucumber";
import checkHttp2 from "is-http2";

//Set global variables.
var isHttp2 = false;

When('we request the homepage via the {string} protocol', (value,done) => {
  let domain = process.env.SERVICE_DOMAIN;

  checkHttp2(domain, { includeSpdy : false } )
    .then(function(result) {
      isHttp2=result.isHttp2;
      done();
    })
    .catch(function(error) {
      console.error(error);
      done(error);
    });
});

Then('we should receive a response via the {string} protocol', (value) => {
  assert.strictEqual(isHttp2,true);
});