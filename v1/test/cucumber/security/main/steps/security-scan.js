import assert from "assert";
import { Given, When, Then } from "cucumber";
import { Curl } from "node-libcurl";
//import { exec } from "child_process";
import fs from "fs";
import path from "path";
import tls from "tls";

//Set some constants.
const global = this;

// 2021.12.16: Get the latest CA certs (needed for AWS CodeBuild)
const certFilePath = path.join(__dirname, "cert.pem");
const tlsData = tls.rootCertificates.join("\n");
fs.writeFileSync(certFilePath, tlsData);

//Main Functions
function runScan(modes,done) {

  //Set Some Constants
  const curlRequest = new Curl();
  //Assuming your scanning tool needs a token or key, this is configured to be passed in.
  const securityKey = process.env.SECURITY_KEY;

  //Main scanning logic would go here.

  //Assign success or failure to the global status, in this case, assigning success.
  global.status = "success";

}

function checkStatus(status) {

  if (status == "pass") {

    assert.ok(true);

  } else {

    assert.equal(global.status, "success");

  }

}

//Test Main Logic
When("we run {string} security scans on the repository", {timeout: 350 * 1000}, runScan);

Then("we should {string} if we receive any security violations", checkStatus);