const assert = require('assert');
const { Given, When, Then } = require('cucumber');
const checkHttp2 = require('is-http2');
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