FROM golang:1.24-alpine AS builder
WORKDIR /app
COPY main.go .
RUN go mod init demo && \
    go get github.com/aws/aws-sdk-go-v2/config && \
    go get github.com/aws/aws-sdk-go-v2/service/s3 && \
    go get github.com/aws/aws-sdk-go-v2/service/bedrockruntime && \
    go build -o server .

FROM alpine:3.19
RUN apk add --no-cache ca-certificates
COPY --from=builder /app/server /server
EXPOSE 8080
CMD ["/server"]
