//Set Modules
var auth = require("basic-auth"), /* Basic Authentication Module */
    fs = require("fs"), /* File System Module */
    http = require("http"), /* Simple HTTP Server Module */
    url = require("url"), /* URL Parsing */
    global = this;

//Main Constants
const APPLICATION_TITLE=process.env.APPLICATION_TITLE || "DEFAULT";
const ENVIRONMENT=process.env.ENVIRONMENT || "NONE";
const REGION=process.env.REGION || "NONE";
const HEALTH_CHECK_PATH=process.env.HEALTH_CHECK_PATH || "/hc/";
const HOSTNAME=process.env.HOSTNAME || "localhost";
const LOGIN=process.env.LOGIN || "DEFAULT";
const PASSWD=process.env.PASSWD || "DEFAULT";
const PORT=process.env.PORT || 8080;


//Main Functions

//Handle request and send response...
function handleRequest(request, response) {

  //Get the credentials...
  var credentials = auth(request),
  parsedUrl = url.parse(request.url);

  //handleRequest Supporting Functions
  function packageFileDetails(err, data) {

    //packageFileDetails Supporting Functions
    function githubFileDetails(err, data) {

      var package = global.package;

      //If we could not read the GitHub file...
      if (err) {

        status = {
          'APP_NAME': package.name,
          'APP_VERSION': package.version
        };
  
        response.writeHead(200, {"Content-Type": "application/json"});
        response.end(JSON.stringify(status));

      //If we could read the GitHub file...
      } else {

        global.git = JSON.parse(data);

        var git = global.git;

        //Change health check output based on environment.
        if (ENVIRONMENT == "prod") {
          status = {
            "APP_NAME": package.name,
            "APP_VERSION": package.version,
            "GIT_COMMIT": git.commit
          };
        } else {
          status = {
            "APP_NAME": package.name,
            "APP_VERSION": package.version,
            "GIT_ORGANIZATION": git.organization,
            "GIT_REPOSITORY": git.repository,
            "GIT_BRANCH": git.branch,
            "GIT_COMMIT": git.commit,
            "GITHUB_COMMIT_URL": git.commitUrl,
            "GITHUB_RELEASE_URL": git.releaseUrl
          };
        }

        response.writeHead(200, {"Content-Type": "application/json"});
        response.end(JSON.stringify(status));

      }

    }

    //Function Logic
    if (err) {

      //If the file request failed for any reason, we still want the health check to work.
      response.writeHead(200, {"Content-Type": "text/plain"});
      response.end("Up");

    } else {

      global.package = JSON.parse(data);

      fs.readFile("/github.json", "utf8", githubFileDetails);

    }

  }

  function displayPage() {

    //The following credentials will have to be replaced with environment variables when this goes to production.
    if (!credentials || credentials.name !== LOGIN || credentials.pass !== PASSWD) {

      //Send an error message if there are bad credentails or no credentials.
      response.statusCode = 401;
      response.setHeader("WWW-Authenticate", "Basic realm=\"Node.js Boilerplate Login\"");
      response.end("Access Denied");

    } else {

      //Return a simple HTML page if we passed Basic Authentication.
      response.writeHead(200, {"Content-Type": "text/html; charset=UTF-8"});
      response.write('<!doctype html>\n<html lang="en">\n' +
                    '<head>\n<meta charset="utf-8">\n<title>' + APPLICATION_TITLE + ' (' + REGION + ')</title>\n' +
                    '<style type="text/css">* {font-family:arial, sans-serif;}</style>\n' +
                    '</head>\n<body>\n' +
                    '<h1>' + APPLICATION_TITLE + ' (' + ENVIRONMENT + ')</h1>\n' +
                    '<div id="content"><p>The ECS Fargate Node.js boilerplate application is now active.</p></div>\n' +
                    '</body>\n</html>');
      response.end();

    }

  }

  //Function Logic

  //If this is the health check path...
  if (parsedUrl.pathname == HEALTH_CHECK_PATH) {

    var status = {};

    fs.readFile("/package.json", "utf8", packageFileDetails);

  //If any other path...
  } else {

    displayPage();

  }

}

function serverSuccess() {

  //Callback triggered when server is successfully listening. Hurray!
  console.log("Server listening on: http://%s:%s", HOSTNAME, PORT);

}

//Main Logic

//Create an HTTP server.
var server = http.createServer(handleRequest);

//Lets start our HTTP server.
server.listen(PORT,serverSuccess);
