# Introduction

This project aims to provide a **management** Azure Kubernetes Service (AKS) cluster, to be used for deploying common useful resources for the development teams within the organization.

## Getting Started

### Prerequisites

- [gitleaks](https://github.com/gitleaks/gitleaks?tab=readme-ov-file#installing)
- [checkov](https://www.checkov.io/2.Basics/Installing%20Checkov.html)

### Setup Git pre-commit hooks

1. Open Git Bash
2. Run the `./init-dev.sh` script

This will install the pre-commit **hooks**, which can be later enriched/modified from within the **.githooks** directory.
