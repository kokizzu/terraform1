FROM golang:1.20 as build1
WORKDIR /app1
COPY go.mod go.sum promfiber.go .
COPY vendor ./vendor
RUN CGO_ENABLED=0 GOOS=linux go build -mod vendor -o app1.exe
# for non vendored, can use this flag to make second build faster (not redownloading)
# --mount=type=cache,target=/go/pkg/mod

# second stage
FROM ubuntu:latest
WORKDIR /
COPY --from=build1 /app1/app1.exe .
CMD ./app1.exe

# total build above took around 7s

# faster way is to build on the CI machine and copy only the binary (only took <1s)
#   time GCO_ENABLED=0 GOOS=linux go build -o app1.exe && docker build .
# the Dockerfile can be something like this:
#FROM ubuntu:latest
#WORKDIR /
#COPY app1.exe .
#CMD ./app1.exe
