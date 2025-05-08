# Introduction

This project aims to provide a **management** Azure Kubernetes Service (AKS) cluster, to be used for deploying common useful resources for the development teams within the organization.

## Getting Started

### Prerequisites

- [terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
- [tflint](https://github.com/terraform-linters/tflint?tab=readme-ov-file#installation)
- [gitleaks](https://github.com/gitleaks/gitleaks?tab=readme-ov-file#installing)
- [checkov](https://www.checkov.io/2.Basics/Installing%20Checkov.html)
- [direnv](https://direnv.net/docs/installation.html)

### Setup Git pre-commit hooks

1. Open Git Bash
2. Run the `./init-dev.sh` script

This will install the pre-commit **hooks**, which can be later enriched/modified from within the **.githooks** directory.

### Setup environment variables

1. Inside the `infrastructure/` directory, create an `.env` file, which is already ignored by .gitignore.
2. Specify your credentials in the `.env` with the following syntax, e.g. `ARM_CLIENT_ID=<your_client_id>`.
3. Once you are finished, run `direnv allow` inside the `infrastructure/` directory.

Now, whenever you `cd` into the `infrastructure/` directory, the environment variables will be **automatically** loaded into your `Git Bash` terminal, and you will be able to run Terraform commands and authenticate against Azure or other providers.
