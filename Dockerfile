ARG GO_VERSION=1.24.4

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION} AS build
ARG TARGETOS
ARG TARGETARCH

WORKDIR /build

RUN go env -w GOPROXY=direct
RUN go install -v github.com/a-h/templ/cmd/templ@latest
RUN go install -v github.com/dlclark/regexp2cg@main

COPY . .
# usually soundcloakctl updates together with soundcloak, so we should redownload it
RUN go install -v git.maid.zone/stuff/soundcloakctl@master
RUN soundcloakctl js download

RUN templ generate
RUN go generate ./lib/*
RUN soundcloakctl config codegen
RUN soundcloakctl -nozstd precompress

RUN CGO_ENABLED=0 GOARCH=${TARGETARCH} GOOS=${TARGETOS} go build -v -ldflags "-s -w -extldflags '-static' -X git.maid.zone/stuff/soundcloak/lib/cfg.Commit=`git rev-parse HEAD | head -c 7` -X git.maid.zone/stuff/soundcloak/lib/cfg.Repo=`git remote get-url origin`" -o ./app
RUN echo "soundcloak:x:5000:5000:Soundcloak user:/:/sbin/nologin" > /etc/minimal-passwd && \
  echo "soundcloak:x:5000:" > /etc/minimal-group

RUN soundcloakctl postbuild
  
FROM scratch

COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build /build/static/assets /static/assets
COPY --from=build /build/static/instance /static/instance
COPY --from=build /build/static/external /static/external
COPY --from=build /build/app /app
COPY --from=build /etc/minimal-passwd /etc/passwd
COPY --from=build /etc/minimal-group /etc/group

EXPOSE 4664

USER soundcloak

ENTRYPOINT ["/app"]
