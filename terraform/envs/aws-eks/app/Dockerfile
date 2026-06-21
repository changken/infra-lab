FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY main.go .
RUN go mod init demo && go build -o server .

FROM alpine:3.19
COPY --from=builder /app/server /server
EXPOSE 8080
CMD ["/server"]
