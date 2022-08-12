# Boilerplate for Deploying a Node.js Application to Fargate using CodePipeline

This repository provides boilerplate for deploying a simple Node.js application to AWS Fargate.

---
**NOTE**

This repository should never be used directly, the "Use this template" button should always be utilized to create fork of this repository.

---

## Table of Contents

- [Version-Specific Documentation](#version-specific-documentation)
- [Project CI/CD Versions](#project-cicd-versions)
- [Design Goals/Highlights](#design-goalshighlights)
- [Frequently Asked Questions (F.A.Q.)](#frequently-asked-questions)
- [License](#license)

# Version-Specific Documentation

- [Version One (v1) README](v1/README.md): Documentation for the main version that uses the current base infrastructure.  Go to this [README](v1/README.md) if you are looking for quick-start instructions.

# Project CI/CD Versions

- [Version One](v1): This version of the boilerplate works with the standard base infrastructure.
    * The standard base infrastructure is located here: [boilerplate-aws-account-setup](https://github.com/warnermedia/boilerplate-aws-account-setup)
    * This version uses manual approval steps to move the current artifacts through the flow.
    * This version is the current active version and the one folks should typically use.

# Design Goals/Highlights

1. Control when infrastructure or application changes are deployed using configuration files.
2. Use a flavor of trunk-based development: https://trunkbaseddevelopment.com/
3. Make use of the GitHub API to help manage patch level revisions.
4. Create formal releases in GitHub using the GitHub API.
5. Minimize the number of GitHub webhooks needed.
6. Create an "orchestrator" to control the retrieval of all source files and distribute them where needed.
7. Allow for deployment to one or two regions.
8. Simplify the creation and management of AWS resources.
9. Make use of Secrets Manager for ECS/Fargate secrets.
10. Make managing of ECS/Fargate environment variables easier.
11. Make load balancers optional for services.
12. Take advantage of the latest CodeBuild/CodePipeline features.
13. Create working examples of application and infrastructure testing.
14. Do some clean-up of the Node.js example service.
15. Encourage the use of "Conventional Commits" to help make commit message more meaningful: https://www.conventionalcommits.org/
16. Separation of duties, using different CodePipelines for different purposes to make things more modular and easier to maintain.
17. Create a helper script to make initial setup easier.
18. Think about how to manage versions from the start (to make things easier to maintain in the future).

# Frequently Asked Questions

1. This `README.md` file has no information on how to get started, where do I start?
    - The detailed documentation for getting started is in the `README.md` for a specific version, so for `v1`, you would go [here](v1/README.md).
2. Why is most of the content in a `v1` folder?
    - The idea is that you can have multiple major versions of your application in one repository.  Perhaps the first version used Node.js and CloudFormation, and now the second version uses Python and Terraform, they can both live in this repository under different base folders.
    - Each version of the product should have the ability to filter out files during the build process.  For instance, in `v1`, you can filter out the `v2` files by using the [orchestrator list files](v1/env/cfn/codebuild/orchestrator).
    - You could also rename `v1` to something like `current`, and then you would eventually have folders such as `previous`, `current`, and `next`.  So you could support a `previous` version for a short period of time, have the `current` active version, but also start developing the `next` version, all in the same repository.
3. Is the `v1` folder required?
    - No, you can choose to exclude the version folder and things should generally work.
    - **NOTE:** Changes are always tested with the `v1` folder in place, so it is possible that there are bugs when trying to remove this folder level, please report the bugs if you find them.
4. Can I use this boilerplate directly?
    - No, you should always fork this repository into your own repository.
    - You always work from a copy of this boilerplate, not the original repository.
    - This repository is set up to be used as a repository template.  Click the "Use this template" button on the main page of the repository to make your own, project-specific copy.
5. This boilerplate is missing functionality, has broken functionality, or I don't like how something works, what do I do?
    - This boilerplate is intended to be a solid starting point for your project.  Since you will be making your own copy of this repository, you can make any changes/enhancements you need to your copy (in order to meet the requirements of your project).
    - If there is missing or broken functionality, please feel free to put in a pull request with the bug fix or enhancement.
    - If you don't like how something works, contact one of the current maintainers to discuss your suggested changes, or put in a pull request with the suggested changes.
    - **NOTE:** Please do not merge in any pull requests to this repository without review from one of the project maintainers.

# License

This repository is released under [the MIT license](https://en.wikipedia.org/wiki/MIT_License).  View the [local license file](./LICENSE).