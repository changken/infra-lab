docker build -t aws-tf .

alias awstf='docker run --rm -it \
  -v "$PWD":"$PWD" -w "$PWD" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v ~/.aws:/root/.aws \
  -v ~/.terraform.d/plugin-cache:/root/.terraform.d/plugin-cache \
  -e TF_PLUGIN_CACHE_DIR=/root/.terraform.d/plugin-cache \
  -e AWS_PROFILE \
  aws-tf'
