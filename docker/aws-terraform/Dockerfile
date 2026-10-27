# ---- 版本集中管理，全部 pin ----
ARG TF_VERSION=1.16
ARG AWSCLI_VERSION=2.38.3
# 依 Lambda runtime 選：build-dotnet8 / build-python3.12 / build-nodejs22.x / build-provided.al2023
ARG SAM_IMAGE=public.ecr.aws/sam/build-dotnet8:1.169.0-20261014204042

FROM hashicorp/terraform:${TF_VERSION} AS tf
FROM amazon/aws-cli:${AWSCLI_VERSION} AS awscli
FROM ${SAM_IMAGE}

# Terraform：static Go binary，直接複製
COPY --from=tf /bin/terraform /usr/local/bin/terraform
# AWS CLI v2：自帶 runtime 的 bundle，整個目錄搬過來後建 symlink
COPY --from=awscli /usr/local/aws-cli /usr/local/aws-cli
RUN ln -sf /usr/local/aws-cli/v2/current/bin/aws /usr/local/bin/aws \
 && terraform -version && aws --version && sam --version

WORKDIR /workspace
