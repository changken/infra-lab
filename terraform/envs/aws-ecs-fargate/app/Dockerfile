FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY main.go .
RUN go mod init app && go build -o server .

FROM alpine:3.21
RUN apk --no-cache add ca-certificates wget
WORKDIR /app
COPY --from=builder /app/server .
EXPOSE 8080
CMD ["./server"]
