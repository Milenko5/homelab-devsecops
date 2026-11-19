# Étape 1 : Compilation statique du binaire Go (sans dépendance C / libc)
FROM golang:1.24-alpine AS builder
WORKDIR /src
COPY main.go .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o /out/demo-app main.go

# Étape 2 : Image finale minimale "FROM scratch" (0 paquet OS, 0 shell, surface d'attaque minimale)
FROM scratch
COPY --from=builder /out/demo-app /demo-app
# Exécution non-root stricte (UID/GID 65532 - conforme au standard Kubernetes PSA Restricted et Checkov CKV_K8S_40)
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/demo-app"]
