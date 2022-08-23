//Set Modules
import auth from "basic-auth"; /* Basic Authentication Module */
import { AppConfigDataClient,
         BadRequestException,
         GetLatestConfigurationCommand,
         StartConfigurationSessionCommand } from "@aws-sdk/client-appconfigdata"; //AWS AppConfig Classes
import fs from "fs"; /* File System Module */
import http from "http"; /* Simple HTTP Server Module */
import path from "path";
import template from "es6-template-strings"; /* Simple templating solution */
import url from "url"; /* URL Parsing */
import YAML from "yaml"; /* YAML parsing */

//Force a specific AWS profile for development.
//process.env.AWS_PROFILE = "<profile>";

//Main Constants
const ENVIRONMENT=process.env.ENVIRONMENT || "NONE",
      REGION=process.env.REGION || "NONE",
      HEALTH_CHECK_PATH=process.env.HEALTH_CHECK_PATH || "/hc/",
      HOSTNAME=process.env.HOSTNAME || "localhost",
      LOGIN=process.env.LOGIN || "DEFAULT",
      PASSWD=process.env.PASSWD || "DEFAULT",
      PORT=process.env.PORT || 8080,
      APP_CONFIG_REGION = process.env.APP_CONFIG_REGION || "us-east-2",
      APP_CONFIG_FEATURE_FLAG_APP_IDENTIFIER = process.env.APP_CONFIG_FEATURE_FLAG_APP_IDENTIFIER || "boilerplate-fargate-appconfig-feature-flag",
      APP_CONFIG_FREEFORM_APP_IDENTIFIER = process.env.APP_CONFIG_FREEFORM_APP_IDENTIFIER || "boilerplate-fargate-appconfig-freeform",
      APP_CONFIG_CONFIG_PROFILE_IDENTIFIER = process.env.APP_CONFIG_CONFIG_PROFILE_IDENTIFIER || "int",
      APP_CONFIG_ENVIRONMENT_IDENTIFIER = process.env.APP_CONFIG_ENVIRONMENT_IDENTIFIER || "int",
      AWS_CONTAINER_CREDENTIALS_FULL_URI = process.env.AWS_CONTAINER_CREDENTIALS_FULL_URI || "NONE",
      AWS_CONTAINER_CREDENTIALS_RELATIVE_URI = process.env.AWS_CONTAINER_CREDENTIALS_RELATIVE_URI || "NONE",
      __filename = url.fileURLToPath(import.meta.url),
      __dirname = path.dirname(__filename);

// AppConfig client (which can be shared by different commands).
const client = new AppConfigDataClient({ region: APP_CONFIG_REGION });

// Parameters for the AppConfig sessions.
const appConfigFeatureFlag = {
  ApplicationIdentifier: APP_CONFIG_FEATURE_FLAG_APP_IDENTIFIER,
  ConfigurationProfileIdentifier: APP_CONFIG_CONFIG_PROFILE_IDENTIFIER,
  EnvironmentIdentifier: APP_CONFIG_ENVIRONMENT_IDENTIFIER
};

const appConfigFreeform = {
  ApplicationIdentifier: APP_CONFIG_FREEFORM_APP_IDENTIFIER,
  ConfigurationProfileIdentifier: APP_CONFIG_CONFIG_PROFILE_IDENTIFIER,
  EnvironmentIdentifier: APP_CONFIG_ENVIRONMENT_IDENTIFIER
};

// New instance for getting an AppConfig session token.
const getFeatureFlagSession = new StartConfigurationSessionCommand(appConfigFeatureFlag),
      getFreeformSession = new StartConfigurationSessionCommand(appConfigFreeform);

//Global Variables
let existingFeatureFlagToken,
    existingFreeformToken,
    global = {},
    htmlFiles = {};

//Set a couple of base global objects.
global.flags = {};
global.config = {};

//Main Functions

function checkCredentials() {

  if (AWS_CONTAINER_CREDENTIALS_FULL_URI === "NONE" && AWS_CONTAINER_CREDENTIALS_RELATIVE_URI === "NONE") {

    console.info("Checking for non-Fargate/ECS credentials...");
    //Make sure that the AWS SDK has credentials before we try to interact with AppConfig.
    Promise.resolve(client.config.credentials()).then(checkFreeformConfig,setDefaultConfigs);

  } else {

    console.info("We are running on either Fargate or ECS...");
    checkFreeformConfig();

  }

}

function checkFeatureFlags() {
  Promise.all([getFeatureFlags()]).then(startService,failure);
}

function checkFreeformConfig() {
  Promise.all([getFreeformConfig()]).then(checkFeatureFlags,failure);
}

// Fail the initialization if the promises fail.
function failure(error) {

  console.error(error);
  return;

}

// Get a single feature flag.
function getFeatureFlag(flag) {

  if (global.flags && flag) {

    return global.flags[flag];

  } else {

    return {};

  }

}

// Get all feature flags for this application and environment.
function getFeatureFlags() {

  console.info("Getting Feature Flag Config...");

  async function _asyncFeatureFlags() {

    if (!existingFeatureFlagToken) {

      existingFeatureFlagToken = await getFeatureFlagToken();

    }

    try {

      // Paramaters for the command.
      const getLatestConfigurationCommand = {
        ConfigurationToken: existingFeatureFlagToken
      };
    
      // Get the lastest configuration.
      const getConfiguration = new GetLatestConfigurationCommand(getLatestConfigurationCommand);

      // Get the configuration.
      const response = await client.send(getConfiguration);

      if (response.Configuration) {

        // The configuration comes back as as set of character codes.
        // Need to convert the character codes into a string.
        let configuration = "";

        for (let i = 0; i < response.Configuration.length; i++) {
          configuration += String.fromCharCode(response.Configuration[i]);
        }

        const allFlags = JSON.parse(configuration);

        global.flags = Object.assign({}, allFlags);

      }

    } catch (error) {

      if (error instanceof BadRequestException) {

        console.error(error);

        existingFeatureFlagToken = await getFeatureFlagToken();

        return _asyncFeatureFlags();

      } else {

        throw error;

      }

    } finally {

      // console.info("complete");

    }

  }

  return _asyncFeatureFlags();

}

// Get the freeform configuration for this application and environment.
function getFreeformConfig() {

  console.info("Getting Freeform Config...");

  async function _asyncFreeformConfig() {

    if (!existingFreeformToken) {

      existingFreeformToken = await getFreeformToken();

    }

    try {

      // Paramaters for the command.
      const getLatestConfigurationCommand = {
        ConfigurationToken: existingFreeformToken
      };
    
      // Get the lastest configuration.
      const getConfiguration = new GetLatestConfigurationCommand(getLatestConfigurationCommand);

      // Get the configuration.
      const response = await client.send(getConfiguration);

      if (response.Configuration) {

        // The configuration comes back as as set of character codes.
        // Need to convert the character codes into a string.
        let configuration = "";

        for (let i = 0; i < response.Configuration.length; i++) {
          configuration += String.fromCharCode(response.Configuration[i]);
        }

        const freeFormConfig = YAML.parse(configuration);

        global.config = Object.assign({}, freeFormConfig);

      }

    } catch (error) {

      if (error instanceof BadRequestException) {

        console.error(error);

        existingFreeformToken = await getFreeformToken();

        return _asyncFreeformConfig();

      } else {

        throw error;

      }

    } finally {

      // console.info("complete");

    }

  }

  return _asyncFreeformConfig();

}

// Get AppConfig Feature Flag token.
async function getFeatureFlagToken() {

  try {

    const sessionToken = await client.send(getFeatureFlagSession);

    return sessionToken.InitialConfigurationToken || "";

  } catch (error) {

    console.error(error);

    throw error;

  } finally {

    // console.info("complete");

  }

}

// Get AppConfig Freeform token.
async function getFreeformToken() {

  try {

    const sessionToken = await client.send(getFreeformSession);

    return sessionToken.InitialConfigurationToken || "";

  } catch (error) {

    console.error(error);

    throw error;

  } finally {

    // console.info("complete");

  }

}

//Handle request and send response...
function handleRequest(request, response) {

  //Get the credentials...
  let credentials = auth(request),
  parsedUrl = url.parse(request.url);

  //handleRequest Supporting Functions
  function displayPage() {

    function preparePage(page) {

      //Proceess the page template.
      return template(page,{Flags:global.flags,Config:global.config});

    }

    //The following credentials will have to be replaced with environment variables when this goes to production.
    if (!credentials || credentials.name !== LOGIN || credentials.pass !== PASSWD) {

      //Send an error message if there are bad credentails or no credentials.
      response.statusCode = 401;
      response.setHeader("WWW-Authenticate", "Basic realm=\"Node.js Boilerplate Login\"");
      response.end("Access Denied");

    } else {

      response.writeHead(200, {"Content-Type": "text/html; charset=UTF-8"});
      response.write(preparePage(htmlFiles["page-header.html"]));

      if (global.flags.header.enabled === true) {
        response.write(preparePage(htmlFiles["body-header-new.html"]));
      } else {
        response.write(preparePage(htmlFiles["body-header-old.html"]));
      }

      response.write(preparePage(htmlFiles["body-main.html"]));

      if (global.flags.footer.enabled === true) {
        response.write(preparePage(htmlFiles["body-footer-new.html"]));
      } else {
        response.write(preparePage(htmlFiles["body-footer-old.html"]));
      }

      response.write(preparePage(htmlFiles["page-footer.html"]));
      response.end();

    }

  }

  function packageFileDetails(err, data) {

    //packageFileDetails Supporting Functions
    function githubFileDetails(err, data) {

      let pkg = global.pkg,
          appInfo = {};

      //If we could not read the GitHub file...
      if (err) {

        appInfo = {
          'APP_NAME': pkg.name,
          'APP_VERSION': pkg.version
        };
  
        response.writeHead(200, {"Content-Type": "application/json"});
        response.end(JSON.stringify(appInfo));

      //If we could read the GitHub file...
      } else {

        global.git = JSON.parse(data);

        let git = global.git;

        //Change health check output based on environment.
        if (ENVIRONMENT == "prod") {
          appInfo = {
            "APP_NAME": pkg.name,
            "APP_VERSION": pkg.version,
            "GIT_COMMIT": git.commit
          };
        } else {
          appInfo = {
            "APP_NAME": pkg.name,
            "APP_VERSION": pkg.version,
            "GIT_ORGANIZATION": git.organization,
            "GIT_REPOSITORY": git.repository,
            "GIT_BRANCH": git.branch,
            "GIT_COMMIT": git.commit,
            "GITHUB_COMMIT_URL": git.commitUrl,
            "GITHUB_RELEASE_URL": git.releaseUrl
          };
        }

        response.writeHead(200, {"Content-Type": "application/json"});
        response.end(JSON.stringify(appInfo));

      }

    }

    //Function Logic
    if (err) {

      //If the file request failed for any reason, we still want the health check to work.
      response.writeHead(200, {"Content-Type": "text/plain"});
      response.end("Up");

    } else {

      global.pkg = JSON.parse(data);

      fs.readFile("/github.json", "utf8", githubFileDetails);

    }

  }

  //Function Logic

  //If this is the health check path...
  if (parsedUrl.pathname == HEALTH_CHECK_PATH) {

    let status = {};

    fs.readFile("/package.json", "utf8", packageFileDetails);

  //If any other path...
  } else {

    displayPage();

  }

}

function init() {

  function getHtmlFiles() {

    let directory = path.join(__dirname, "html");
    let fileList = fs.readdirSync(directory);
    //let promises = fileList.map(file => readFileContent(path.join(directory, file),file));

    function readFileContent(file) {
  
      function _readFileContent(resolve, reject) {
  
        function parseFile(error, data) {
  
          if (error) {
            reject(error);
          }

          // function parseLine(line) {
          //   return line.trim();
          // }

          //let fileContent = data.toString().split(/(?:\r\n|\r|\n)/g).map(parseLine).filter(Boolean);
          let fileContent = data.toString();
      
          resolve(processFile(file,fileContent));
      
        }
  
        fs.readFile(path.join(directory, file), parseFile);
  
      }
  
      let output = new Promise(_readFileContent);
  
      return output;
  
    }

    let promises = fileList.map(readFileContent);

    Promise.all(promises).then(checkCredentials,failure);

  }

  function processFile(file,fileContent) {

    htmlFiles[file] = fileContent;

    console.log(`File Name: ${file}`);

  }

  getHtmlFiles();

}

function setDefaultConfigs() {

  console.warn("No valid AWS SDK credentials were found.");

  console.warn(`process.env.AWS_CONTAINER_CREDENTIALS_FULL_URI: ${process.env.AWS_CONTAINER_CREDENTIALS_FULL_URI}`);
  console.warn(`process.env.AWS_CONTAINER_CREDENTIALS_RELATIVE_URI: ${process.env.AWS_CONTAINER_CREDENTIALS_RELATIVE_URI}`);

  //Set a generic default config since there are no credentials for the AWS SDK.
  global.config = {
    Body: {
      Author: "Default Author",
      Description: "Default Description",
      Image: "https://via.placeholder.com/300",
      Subtitle: "Default Subtitle",
      Title: "AppConfig Feature Flag and Freeform Config Demo Site",
      Type: "website",
      Url: "www.example.com"
    }
  };

  //Set some default falgs since there are no credentials for the AWS SDK.
  global.flags = {
    footer: {
      enabled: false
    },
    header: {
      enabled: false
    }
  };

  //Start the service with the default values.
  startService();

}

function startService() {

  console.info("AppConfig Freeform Config...");
  console.dir(global.config);
  console.info("AppConfig Feature Flags Config...");
  console.dir(global.flags);

  function serverSuccess() {

    //Callback triggered when server is successfully listening. Hurray!
    console.log("Server listening on: http://%s:%s", HOSTNAME, PORT);
  
  }
  
  //Main Logic
  
  //Create an HTTP server.
  let server = http.createServer(handleRequest);
  
  //Lets start our HTTP server.
  server.listen(PORT,serverSuccess);

}

init();