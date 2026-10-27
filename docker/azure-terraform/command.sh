docker build -t az-tf .
alias aztf='docker run --rm -it -v "$PWD":/workspace -v ~/.azure:/root/.azure az-tf'

aztf az login --use-device-code
aztf terraform init
aztf terraform apply
