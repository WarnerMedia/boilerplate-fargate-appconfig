import assert from "assert";
import { Given, When, Then } from "@cucumber/cucumber";
import http2 from "node:http2";

//Set global variables.
let isHttp2 = false;

When('we connect via the {string} protocol', (value,done) => {

  function testHttp2() {

    let domain = process.env.SERVICE_DOMAIN;

    const client = http2.connect(`https://${domain}:443`);

    client.setTimeout(10000); //Set the timer for five seconds.

    function returnClientError(error) {
  
      console.error(error.code);
  
      if (error.code == "ERR_HTTP2_ERROR") {
  
        console.info("HTTP/2 is not enabled.");
  
      } else {
  
        console.error("Some other connection error.");
  
      }
  
      isHttp2 = false;
  
      client.close();

      done(error);
  
    }
  
    function returnClientConnect() {
  
      console.info("Connection is ready...");

      /* Set the flag to true, because a connection was made,
         we might still get an HTTP/2 error, but that will come later */
      isHttp2 = true;
  
      function waitHttp2Check() {
  
        console.info("Closing the connection...");
        client.close();
        done();
  
      }
  
      setTimeout(waitHttp2Check, 3000);
  
    }
  
    function returnClientTimeout() {
  
      console.warn("Timeout reached wihtout error...");
  
      client.close();

      done();
  
    }
  
    client.on("error", returnClientError);
  
    client.on("timeout", returnClientTimeout);
  
    client.on("connect",returnClientConnect);

  }

  try {

    testHttp2();
  
  } catch(error) {
  
    isHttp2 = false;
  
    console.error(error.code);

    done(error);

  }

});

Then('we should not receive a connection error', (value) => {

  assert.strictEqual(isHttp2,true);

});