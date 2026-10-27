FROM hashicorp/terraform:1.16 AS tf
FROM mcr.microsoft.com/azure-cli:2.91.0-azurelinux4.0
COPY --from=tf /bin/terraform /usr/local/bin/terraform
WORKDIR /workspace
