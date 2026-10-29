FROM golang:1.26-alpine AS build

WORKDIR /src
COPY go.mod ./
COPY . .

RUN CGO_ENABLED=0 GOOS=linux go test ./... \
    && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /server .

FROM scratch

COPY --from=build /server /server
USER 65532:65532
ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["/server"]
