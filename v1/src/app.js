//Set Modules
import auth from "basic-auth"; /* Basic Authentication Module */
import { AppConfigDataClient,
         BadRequestException,
         GetLatestConfigurationCommand,
         StartConfigurationSessionCommand } from "@aws-sdk/client-appconfigdata"; //AWS AppConfig Classes
import cache from "cache"; /* Simple caching Module */
import fs from "fs"; /* File System Module */
import http from "http"; /* Simple HTTP Server Module */
import path from "path";
import template from "es6-template-strings"; /* Simple templating solution */
import url from "url"; /* URL Parsing */
import YAML from "yaml"; /* YAML parsing */

//Force a specific AWS profile for development.
//process.env.AWS_PROFILE = "<profile>";

//Main Constants
const __filename = url.fileURLToPath(import.meta.url),
      __dirname = path.dirname(__filename),
      APP_CONFIG_CACHE = process.env.APP_CONFIG_CACHE || 15, /* AppConfig cache time in seconds  */
      APP_CONFIG_REGION = process.env.APP_CONFIG_REGION || "us-east-2",
      APP_CONFIG_FEATURE_FLAG_APP_IDENTIFIER = process.env.APP_CONFIG_FEATURE_FLAG_APP_IDENTIFIER || "boilerplate-fargate-appconfig-feature-flag",
      APP_CONFIG_FREEFORM_APP_IDENTIFIER = process.env.APP_CONFIG_FREEFORM_APP_IDENTIFIER || "boilerplate-fargate-appconfig-freeform",
      APP_CONFIG_CONFIG_PROFILE_IDENTIFIER = process.env.APP_CONFIG_CONFIG_PROFILE_IDENTIFIER || "int",
      APP_CONFIG_ENVIRONMENT_IDENTIFIER = process.env.APP_CONFIG_ENVIRONMENT_IDENTIFIER || "int",
      ENVIRONMENT=process.env.ENVIRONMENT || "NONE",
      HEALTH_CHECK_PATH=process.env.HEALTH_CHECK_PATH || "/hc/",
      HOSTNAME=process.env.HOSTNAME || "localhost",
      LOGIN=process.env.LOGIN || "DEFAULT",
      PASSWD=process.env.PASSWD || "DEFAULT",
      PORT=process.env.PORT || 8080,
      REGION=process.env.REGION || "NONE";

// AppConfig client (which can be shared by different commands).
const client = new AppConfigDataClient({ region: APP_CONFIG_REGION }),
      configCache = new cache(APP_CONFIG_CACHE * 1000); /* Cache with 10-second TTL */

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

  console.info("Checking for AWS credentials...");

  //Make sure that the AWS SDK has credentials before we try to interact with AppConfig.
  Promise.resolve(client.config.credentials()).then(fillConfigCache,setDefaultConfigs);

}

// Fail the initialization if the promises fail.
function failure(error) {

  console.error(error);
  return;

}

function fillConfigCache() {

  //Get both configurations and putting them in a basic cache.
  Promise.all([getFreeformConfig(),getFeatureFlags()]).then(startService,failure);

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

        configCache.put("flags",global.flags);

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

        configCache.put("config",global.config);

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

  function checkCache() {

    let config = configCache.get("config"),
        flags = configCache.get("flags");

    if (config == null || flags == null) {

      console.info("Cache is empty, need to reset...");
      Promise.all([getFreeformConfig(),getFeatureFlags()]).then(displayHomepage,failure);

    } else {

      console.info("Cache is set, loading the homepage...");
      displayHomepage();

    }

  }

  function displayBasicAuth() {

      //Send an error message if there are bad credentails or no credentials.
      response.statusCode = 401;
      response.setHeader("WWW-Authenticate", "Basic realm=\"Basic Auth Login\"");
      response.end("Access Denied");

  }

  function displayHealthCheck(err, data) {

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

  function displayHomepage() {

    let cssContent = preparePage(htmlFiles["html/css/style-old.html"]);

    if (global.flags.header.enabled === true || global.flags.footer.enabled === true) {

      cssContent = preparePage(htmlFiles["html/css/style-new.html"]);

    }

    response.writeHead(200, {"Content-Type": "text/html; charset=UTF-8"});
    response.write(preparePage(htmlFiles["html/page/header.html"],cssContent));

    if (global.flags.header.enabled === true) {

      response.write(preparePage(htmlFiles["html/body/header-new.html"]));

    } else {

      response.write(preparePage(htmlFiles["html/body/header-old.html"]));

    }

    response.write(preparePage(htmlFiles["html/body/main.html"]));

    if (global.flags.footer.enabled === true) {

      response.write(preparePage(htmlFiles["html/body/footer-new.html"]));

    } else {

      response.write(preparePage(htmlFiles["html/body/footer-old.html"]));

    }

    response.write(preparePage(htmlFiles["html/page/footer.html"]));
    response.end();

  }

  function displayPage() {

    if (!credentials || credentials.name !== LOGIN || credentials.pass !== PASSWD) {

      displayBasicAuth();

    } else {

      checkCache();

    }

  }

  function preparePage(page,cssContent) {

    let CSS_CONTENT = cssContent || "";

    //Proceess the page template.
    return template(page,{config:configCache.get("config"),flags:configCache.get("flags"),CSS_CONTENT:CSS_CONTENT});

  }

  //Function Logic

  //If this is the health check path...
  if (parsedUrl.pathname == HEALTH_CHECK_PATH) {

    let status = {};

    fs.readFile("/package.json", "utf8", displayHealthCheck);

  //If any other path...
  } else {

    displayPage();

  }

}

function init() {

  function getHtmlFiles(baseDirectory) {

    let directory = path.join(__dirname, baseDirectory);
    let fileList = fs.readdirSync(directory);
    //let promises = fileList.map(file => readFileContent(path.join(directory, file),file));

    function readFileContent(file) {
  
      function _readFileContent(resolve, reject) {
  
        function parseFile(error, data) {
  
          if (error) {
            reject(error);
          }

          let fileContent = data.toString();
      
          resolve(processFile(baseDirectory,file,fileContent));
      
        }
  
        fs.readFile(path.join(directory, file), parseFile);
  
      }
  
      let output = new Promise(_readFileContent);
  
      return output;
  
    }

    let promises = fileList.map(readFileContent);

    return promises;

  }

  function processFile(directory,file,fileContent) {


    htmlFiles[`${directory}/${file}`] = fileContent;

    console.log(`File Name: ${directory}/${file}`);

  }

  Promise.all([getHtmlFiles("html/body"),getHtmlFiles("html/css"),getHtmlFiles("html/page")].flat()).then(checkCredentials,failure);

}

function setDefaultConfigs() {

  console.warn("No valid AWS SDK credentials were found.");

  //Set a generic default config since there are no credentials for the AWS SDK.
  global.config = {
    body: {
      author: "Default Author",
      description: "Default Description",
      image: "https://via.placeholder.com/300",
      subtitle: "Default Subtitle",
      title: "AppConfig Feature Flag and Freeform Config Demo Site",
      type: "website",
      url: "www.example.com"
    }
  };

  configCache.put("config",global.config);

  //Set some default falgs since there are no credentials for the AWS SDK.
  global.flags = {
    footer: {
      enabled: false
    },
    header: {
      enabled: false
    }
  };

  configCache.put("flags",global.flags);

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