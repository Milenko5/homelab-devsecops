package main

import (
	"fmt"
	"html"
	"net/http"
	"os"
	"strings"
	"time"
)

func readSecretFile(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

func main() {
	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("OK"))
	})

	mux.HandleFunc("/", func(w http.ResponseWriter, _ *http.Request) {
		hostname, _ := os.Hostname()
		dbUser := readSecretFile("/etc/secrets/DB_USERNAME")
		dbHost := readSecretFile("/etc/secrets/DB_HOST")
		dbPass := readSecretFile("/etc/secrets/DB_PASSWORD")

		vaultStatus := "❌ Non injecté"
		if dbUser != "" && dbPass != "" {
			vaultStatus = fmt.Sprintf("✅ Synchronisé via ESO (User: %s | Host: %s | Password: %d octets en mémoire)",
				html.EscapeString(dbUser), html.EscapeString(dbHost), len(dbPass))
		}

		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		fmt.Fprintf(w, `<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <title>Homelab DevSecOps - Zero Trust Demo App</title>
  <style>
    body { font-family: system-ui, -apple-system, sans-serif; background: #0f172a; color: #f8fafc; margin: 0; padding: 2rem; }
    .card { max-width: 780px; margin: 2rem auto; background: #1e293b; border: 1px solid #334155; border-radius: 12px; padding: 2rem; box-shadow: 0 10px 25px rgba(0,0,0,0.4); }
    h1 { color: #38bdf8; margin-top: 0; font-size: 1.6rem; }
    .badge { display: inline-block; background: #065f46; color: #6ee7b7; padding: 0.25rem 0.75rem; border-radius: 999px; font-size: 0.85rem; font-weight: 600; margin-bottom: 1rem; }
    .row { display: flex; justify-content: space-between; padding: 0.85rem 0; border-bottom: 1px solid #334155; }
    .label { color: #94a3b8; font-weight: 500; }
    .value { color: #e2e8f0; font-family: monospace; text-align: right; }
  </style>
</head>
<body>
  <div class="card">
    <span class="badge">🛡️ ZERO-TRUST SUPPLY CHAIN VERIFIED</span>
    <h1>Laboratoire DevSecOps Bare-Metal HA (sysdev.ca)</h1>
    <div class="row"><span class="label">Pod Réplica Actif</span><span class="value">%s</span></div>
    <div class="row"><span class="label">UID / Profil PSA Kubernetes</span><span class="value">UID %d (Restricted / Read-Only RootFS)</span></div>
    <div class="row"><span class="label">Secret Dynamique HashiCorp Vault (DRBD 9)</span><span class="value">%s</span></div>
    <div class="row"><span class="label">Chaîne d'Approvisionnement OCI</span><span class="value">✅ Syft SBOM + Grype Scan + Cosign Keyless OIDC</span></div>
    <div class="row"><span class="label">Contrôle d'Admission Runtime</span><span class="value">✅ Kyverno verifyImages (Enforce + Digest Mutation)</span></div>
    <div class="row"><span class="label">Horodatage Serveur (UTC)</span><span class="value">%s</span></div>
  </div>
</body>
</html>`, html.EscapeString(hostname), os.Getuid(), vaultStatus, time.Now().UTC().Format(time.RFC3339))
	})

	server := &http.Server{
		Addr:              ":8080",
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}
	if err := server.ListenAndServe(); err != nil {
		os.Exit(1)
	}
}
