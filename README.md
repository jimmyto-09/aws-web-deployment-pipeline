# DevOps Project: Automated Web Deployment on AWS

A web application deployed on AWS using Terraform, Ansible, Docker Compose, and GitHub Actions. The application is served through a custom domain with HTTPS.

**Live site:** https://app.jimmyto09.site

## How it works

1. **Terraform** provisions the AWS infrastructure: VPC, networking, EC2 instance, Application Load Balancer, ACM certificate, and Route 53 DNS record.
2. **Docker Compose** runs an Nginx container on the EC2 instance to serve the web page.
3. A push to the `main` branch triggers the **GitHub Actions** deployment workflow.
4. A self-hosted runner executes **Ansible**, which connects to the EC2 instance over SSH and publishes the application files.
5. Visitors reach the site through the custom domain. Route 53 directs traffic to the load balancer, which forwards requests to Nginx on EC2.

## Technologies

- **AWS:** EC2, VPC, Application Load Balancer, ACM, and Route 53
- **Terraform:** infrastructure provisioning
- **Ansible:** server configuration and application deployment
- **Docker Compose and Nginx:** application hosting
- **GitHub Actions:** automated deployment with a self-hosted runner

## Project structure

```text
.
├── .github/workflows/deploy.yml  # GitHub Actions deployment workflow
├── ansible/deploy.yml             # EC2 configuration and deployment
├── app/
│   ├── compose.yaml               # Nginx container configuration
│   └── index.html                 # Web page
└── terraform/                     # AWS infrastructure
```

## Deployment flow

To publish an application change:

1. Edit `app/index.html`.
2. Commit and push the change to `main`.
3. GitHub Actions runs the Ansible playbook on the self-hosted runner.
4. Ansible copies the updated files to EC2.
5. Check the deployed page at https://app.jimmyto09.site.

The workflow also checks that the application responds after deployment.

## Environment note

The self-hosted GitHub Actions runner runs on my local WSL environment, so it must be online to process deployments. Terraform manages the AWS infrastructure separately; the current workflow automates application deployment.
