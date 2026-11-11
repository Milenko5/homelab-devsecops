#!/bin/bash

# Fail-fast: exit si une commande échoue ou si une variable non définie est utilisée
set -e
set -o pipefail
set -u

# Fonction pour afficher les messages d'erreur et quitter
function error_exit {
    echo "ERREUR: $1" >&2
    exit 1
}

# Fonction pour vérifier si une commande existe
function check_command {
    command -v "$1" >/dev/null 2>&1 || error_exit "La commande '$1' n'est pas installée. Veuillez l'installer et réessayer."
}

# Fonction pour valider une adresse e-mail
function validate_email {
    local email="$1"
    # Validation d'email basique
    if [[ ! "${email}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        error_exit "L'adresse e-mail '${email}' est invalide."
    fi
}

# Fonction pour valider le nom
function validate_name {
    local name="$1"
    if [[ ! "${name}" =~ ^[a-zA-Z0-9\[:space:\]-]+$ ]]; then
        error_exit "Le nom '${name}' contient des caractères invalides."
    fi
}

# Fonction pour vérifier l'état de la clé (expirée, révoquée, valide)
function check_key_status {
    local KEY_ID="$1"
    local EMAIL="$2"
    
    # Récupérer les informations de la clé avec le format colons
    local KEY_INFO
    KEY_INFO=$(gpg --batch --no-tty --with-colons --list-secret-keys "${EMAIL}" 2>/dev/null | grep '^sec:' | head -1)
    
    if [[ -z "${KEY_INFO}" ]]; then
        error_exit "Impossible de récupérer les informations de la clé GPG."
    fi
    
    # Extraire les champs du format colons
    # Format: sec:[TRUST]:[LENGTH]:[ALGO]:[KEY_ID]:[CREATION]:[EXPIRATION]:[VALIDITY]:...
    local VALIDITY
    local EXPIRATION
    
    VALIDITY=$(echo "${KEY_INFO}" | cut -d: -f2)  # Champ 2 = TRUST
    EXPIRATION=$(echo "${KEY_INFO}" | cut -d: -f7)
    
    # Vérifier si la clé est révoquée
    if [[ "${VALIDITY}" == "r" ]]; then
        return 2  # Code: clé révoquée
    fi
    
    # Vérifier si la clé est expirée
    local CURRENT_DATE
    CURRENT_DATE=$(date +%s)
    
    if [[ -n "${EXPIRATION}" && "${EXPIRATION}" -gt 0 ]]; then
        if [[ "${EXPIRATION}" -lt "${CURRENT_DATE}" ]]; then
            return 1  # Code: clé expirée
        else
            return 0  # Code: clé valide
        fi
    else
        return 0  # Clé sans expiration = valide
    fi
}

# Fonction pour afficher le statut d'expiration d'une clé
function check_expiration {
    local EMAIL="$1"
    
    validate_email "${EMAIL}"
    
    echo "Vérification de la clé GPG pour ${EMAIL}..."
    echo ""
    
    # Récupérer l'identifiant de la clé
    local KEY_ID
    if ! KEY_ID=$(gpg --batch --no-tty --with-colons --list-secret-keys "${EMAIL}" 2>/dev/null | grep '^sec:' | cut -d: -f5 | head -1); then
        error_exit "Impossible de rechercher la clé GPG."
    fi
    
    if [[ -z "${KEY_ID}" ]]; then
        error_exit "❌ Aucune clé GPG trouvée pour ${EMAIL}."
    fi
    
    echo "Clé GPG trouvée avec l'ID: ${KEY_ID}"
    echo ""
    
    # Récupérer les informations de la clé
    local KEY_INFO
    KEY_INFO=$(gpg --batch --no-tty --with-colons --list-secret-keys "${EMAIL}" 2>/dev/null | grep '^sec:' | head -1)
    
    local VALIDITY
    local EXPIRATION
    
    VALIDITY=$(echo "${KEY_INFO}" | cut -d: -f2)  # Champ 2 = TRUST
    EXPIRATION=$(echo "${KEY_INFO}" | cut -d: -f7)
    
    # Vérifier l'état de la clé
    if [[ "${VALIDITY}" == "r" ]]; then
        echo "🔴 Statut: RÉVOQUÉE"
        echo "Action requise: Créer une nouvelle clé avec './scripts/gererGPGKeys.sh renew ${EMAIL} --new'"
        return 2
    fi
    
    if [[ -n "${EXPIRATION}" && "${EXPIRATION}" -gt 0 ]]; then
        local CURRENT_DATE
        CURRENT_DATE=$(date +%s)
        
        if [[ "${EXPIRATION}" -lt "${CURRENT_DATE}" ]]; then
            echo "⚠️  Statut: EXPIRÉE"
            echo "Date d'expiration: $(date -d @"${EXPIRATION}" '+%d/%m/%Y')"
            echo "Action requise: Renouveler avec './scripts/gererGPGKeys.sh renew ${EMAIL}'"
            return 1
        else
            local DAYS_LEFT
            DAYS_LEFT=$(( (EXPIRATION - CURRENT_DATE) / 86400 ))
            local HOURS_LEFT
            HOURS_LEFT=$(( ((EXPIRATION - CURRENT_DATE) % 86400) / 3600 ))
            
            if [[ ${DAYS_LEFT} -eq 0 ]]; then
                echo "⏰ Statut: EXPIRE DANS ${HOURS_LEFT} heure(s)"
            else
                echo "✅ Statut: VALIDE"
                echo "Expire dans: ${DAYS_LEFT} jour(s) et ${HOURS_LEFT} heure(s)"
            fi
            echo "Date d'expiration: $(date -d @"${EXPIRATION}" '+%d/%m/%Y')"
            return 0
        fi
    else
        echo "✅ Statut: VALIDE (sans date d'expiration)"
        return 0
    fi
}

# Fonction pour créer une nouvelle clé GPG
function create_new_key {
    local NAME="$1"
    local EMAIL="$2"
    
    # Validation des informations
    if [[ -z "${NAME}" ]]; then
        read -rp "Entrez votre nom et prénom (ex: John Doe) : " NAME
    fi
    
    if [[ -z "${EMAIL}" ]]; then
        read -rp "Entrez votre adresse e-mail (ex: john.doe@example.com) : " EMAIL
    fi
    
    if [[ -z "${NAME}" || -z "${EMAIL}" ]]; then
        error_exit "Le nom ou l'adresse e-mail ne peuvent pas être vides."
    fi
    
    # Validation des entrées
    validate_name "${NAME}"
    validate_email "${EMAIL}"
    
    echo "Génération d'une nouvelle clé GPG..."
    echo ""
    
    # Génération de la clé GPG
    # Solution pour WSL2: utiliser un fichier temporaire au lieu d'un heredoc
    # Cela évite l'erreur "gpg: -:X: missing argument" sur WSL2
    local TEMP_KEY_CONFIG
    TEMP_KEY_CONFIG=$(mktemp)
    
    cat > "${TEMP_KEY_CONFIG}" << 'GPGCONFIG'
Key-Type: 1
Key-Length: 4096
Subkey-Type: 1
Subkey-Length: 4096
Name-Real: PLACEHOLDER_NAME
Name-Email: PLACEHOLDER_EMAIL
Expire-Date: 370d
%no-protection
%commit
GPGCONFIG

    # Remplacer les placeholders dans le fichier temporaire
    sed -i "s/PLACEHOLDER_NAME/${NAME}/g" "${TEMP_KEY_CONFIG}"
    sed -i "s/PLACEHOLDER_EMAIL/${EMAIL}/g" "${TEMP_KEY_CONFIG}"
    # Générer la clé en utilisant le fichier de configuration
    if ! gpg --batch --no-tty --full-gen-key < "${TEMP_KEY_CONFIG}"; then
        rm -f "${TEMP_KEY_CONFIG}"
        error_exit "La génération de la clé GPG a échoué. Veuillez vérifier les logs."
    fi
    
    # Nettoyer le fichier temporaire
    rm -f "${TEMP_KEY_CONFIG}"
    
    # Récupérer l'identifiant de la clé
    local KEY_ID
    if ! KEY_ID=$(gpg --batch --no-tty --with-colons --list-secret-keys "${EMAIL}" 2>/dev/null | grep '^sec:' | cut -d: -f5 | head -1); then
        error_exit "Impossible de récupérer l'identifiant de la clé GPG."
    fi
    
    if [[ -z "${KEY_ID}" ]]; then
        error_exit "Impossible de trouver l'identifiant de la nouvelle clé GPG."
    fi
    
    echo "Nouvelle clé GPG avec l'ID: ${KEY_ID} a été créée."
    echo ""
    
    # Calculer la date d'expiration (370 jours à partir d'aujourd'hui)
    local EXPIRATION_DATE
    if ! EXPIRATION_DATE=$(date -d "+370 days" "+%d/%m/%Y"); then
        error_exit "Impossible de calculer la date d'expiration."
    fi
    
    # Configuration de Git pour utiliser la nouvelle clé
    echo "Configuration de Git pour utiliser cette clé pour la signature des commits..."
    if ! git config --global user.signingkey "${KEY_ID}"; then
        error_exit "Impossible de configurer Git avec la clé de signature."
    fi
    if ! git config --global commit.gpgsign true; then
        error_exit "Impossible de configurer la signature GPG par défaut dans Git."
    fi
    
    echo "✅ Git configuré avec succès !"
    echo ""
    
    # Afficher la clé publique pour l'ajouter à GitHub
    echo "---"
    echo "Clé publique GPG (copiez-la et ajoutez-la à votre compte GitHub) :"
    echo "---"
    if ! gpg --batch --no-tty --armor --export "${KEY_ID}"; then
        error_exit "Impossible d'exporter la clé publique GPG."
    fi
    
    echo "---"
    echo "✅ Fini ! Tes commits seront maintenant signés par défaut. N'oublie pas d'ajouter la clé publique ci-dessus à ton profil GitHub pour que tes commits apparaissent comme 'Verified'."
    echo ""
    echo "📅 Expiration de la clé: ${EXPIRATION_DATE}"
    echo ""
    echo "Pour renouveler cette clé à l'avenir, utilise:"
    echo "  ./scripts/gererGPGKeys.sh renew ${EMAIL}"
    echo "ou simplement:"
    echo "  ./scripts/gererGPGKeys.sh renew"
}


function renew_key {
    local EMAIL="$1"
    local FORCE="${2:-}"
    
    # Validation de l'email
    validate_email "${EMAIL}"
    
    echo "Recherche de la clé GPG pour ${EMAIL}..."
    
    # Récupérer l'identifiant de la clé
    local KEY_ID
    if ! KEY_ID=$(gpg --batch --no-tty --with-colons --list-secret-keys "${EMAIL}" 2>/dev/null | grep '^sec:' | cut -d: -f5 | head -1); then
        error_exit "Impossible de rechercher la clé GPG."
    fi
    
    if [[ -z "${KEY_ID}" ]]; then
        echo "❌ Aucune clé GPG trouvée pour ${EMAIL}."
        echo ""
        echo "Voulez-vous créer une nouvelle clé ? (o/n)"
        read -rp "Réponse: " response
        if [[ "${response}" =~ ^[oO]$ ]]; then
            create_new_key "" "${EMAIL}"
        else
            error_exit "Opération annulée."
        fi
        return
    fi
    
    echo "Clé GPG trouvée avec l'ID: ${KEY_ID}"
    echo ""
    
    # Récupérer les informations de la clé
    local KEY_INFO
    KEY_INFO=$(gpg --batch --no-tty --with-colons --list-secret-keys "${EMAIL}" 2>/dev/null | grep '^sec:' | head -1)
    
    local VALIDITY
    local EXPIRATION
    
    VALIDITY=$(echo "${KEY_INFO}" | cut -d: -f2)  # Champ 2 = TRUST
    EXPIRATION=$(echo "${KEY_INFO}" | cut -d: -f7)
    
    # Vérifier l'état de la clé
    if [[ "${VALIDITY}" == "r" ]]; then
        echo "🔴 La clé GPG est RÉVOQUÉE."
        echo ""
        if [[ "${FORCE}" == "--new" ]]; then
            echo "Création d'une nouvelle clé..."
            # Récupérer le nom de l'utilisateur
            local NAME
            NAME=$(gpg --batch --no-tty --with-colons --list-secret-keys "${EMAIL}" 2>/dev/null | grep '^uid:' | cut -d: -f10 | cut -d'<' -f1 | xargs | head -1)
            if [[ -z "${NAME}" ]]; then
                read -rp "Entrez votre nom et prénom : " NAME
            fi
            create_new_key "${NAME}" "${EMAIL}"
        else
            error_exit "Une nouvelle clé doit être créée. Utilisez: ./scripts/gererGPGKeys.sh renew ${EMAIL} --new"
        fi
        return
    fi
    
    # Afficher l'état d'expiration
    if [[ -n "${EXPIRATION}" && "${EXPIRATION}" -gt 0 ]]; then
        local CURRENT_DATE
        CURRENT_DATE=$(date +%s)
        
        if [[ "${EXPIRATION}" -lt "${CURRENT_DATE}" ]]; then
            echo "⚠️  La clé GPG est EXPIRÉE (depuis le $(date -d @"${EXPIRATION}" '+%d/%m/%Y'))."
        else
            local DAYS_LEFT
            DAYS_LEFT=$(( (EXPIRATION - CURRENT_DATE) / 86400 ))
            echo "ℹ️  La clé GPG expire dans ${DAYS_LEFT} jour(s) (le $(date -d @"${EXPIRATION}" '+%d/%m/%Y'))."
        fi
    else
        echo "ℹ️  La clé GPG n'a pas de date d'expiration."
    fi
    
    if [[ "${FORCE}" != "--force" ]]; then
        echo ""
        echo "Êtes-vous sûr de vouloir renouveler cette clé ? (o/n)"
        read -rp "Réponse: " response
        if [[ ! "${response}" =~ ^[oO]$ ]]; then
            echo "Opération annulée."
            return
        fi
    fi
    
    echo ""
    echo "Renouvellement de la clé GPG..."
    
    # Renouveler la clé (étendre la date d'expiration à 370 jours)
    if ! gpg --batch --no-tty --quick-set-expire "${KEY_ID}" +370d; then
        error_exit "❌ Le renouvellement de la clé GPG a échoué. Vérifiez que la clé n'est pas corrompue."
    fi
    
    # Calculer la nouvelle date d'expiration
    local NEW_EXPIRATION
    if ! NEW_EXPIRATION=$(date -d "+370 days" "+%d/%m/%Y"); then
        error_exit "Impossible de calculer la nouvelle date d'expiration."
    fi
    
    echo "✅ Clé GPG renouvelée avec succès !"
    echo "📅 Nouvelle expiration: ${NEW_EXPIRATION}"
    echo ""
    echo "Nouvelle clé publique :"
    if ! gpg --batch --no-tty --armor --export "${KEY_ID}"; then
        error_exit "Impossible d'exporter la clé publique GPG."
    fi
}

# Vérification des commandes requises
check_command "gpg"
check_command "git"

# Fonction pour afficher l'aide
function show_help {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  renew EMAIL [--force] [--new]     Renouveler la clé GPG pour EMAIL"
    echo "                                    --force: Ne pas demander de confirmation"
    echo "                                    --new: Créer une nouvelle clé si celle-ci est révoquée"
    echo "  check EMAIL                       Vérifier l'état d'expiration de la clé pour EMAIL"
    echo "  (no command)                      Créer une nouvelle clé GPG"
    echo ""
    echo "Examples:"
    echo "  $0 renew john@example.com"
    echo "  $0 renew john@example.com --force"
    echo "  $0 renew john@example.com --new"
    echo "  $0 check john@example.com"
    echo "  $0"
}

# Traitement des arguments
if [[ "${1:-}" == "renew" ]]; then
    if [[ -z "${2:-}" ]]; then
        read -rp "Entrez l'adresse e-mail de la clé à renouveler : " EMAIL
    else
        EMAIL="${2}"
    fi
    # Traiter les options --force et --new
    if [[ -n "${3:-}" ]]; then
        renew_key "${EMAIL}" "${3}"
    else
        renew_key "${EMAIL}"
    fi
    exit 0
elif [[ "${1:-}" == "check" ]]; then
    if [[ -z "${2:-}" ]]; then
        read -rp "Entrez l'adresse e-mail de la clé à vérifier : " EMAIL
    else
        EMAIL="${2}"
    fi
    check_expiration "${EMAIL}"
    exit 0
elif [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    show_help
    exit 0
elif [[ -n "${1:-}" ]]; then
    echo "Commande inconnue: ${1}"
    echo ""
    show_help
    exit 1
fi

# Demande des informations de l'utilisateur
read -rp "Entrez votre nom et prénom (ex: John Doe) : " NAME
read -rp "Entrez votre adresse e-mail (ex: john.doe@example.com) : " EMAIL

create_new_key "${NAME}" "${EMAIL}"