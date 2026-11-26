#!/usr/bin/env bash
set -euo pipefail

# Run after hospital_full.sql and database/02_roles_grants.sql.
# Configures authentication without changing the existing roles.

CONTAINER="${HOSPITAL_DB_CONTAINER:-hospital-db}"

# Temporary credentials must never be readable by other users.
umask 077

# Clear password variables when the script finishes or fails.

cleanup() {
    # Remove temporary credentials from the Docker container.
    if [[ -n "${CONTAINER_CNF:-}" ]]; then
        docker exec -u root "$CONTAINER" \
            rm -f -- "$CONTAINER_CNF" 2>/dev/null || true
    fi

    # Remove temporary credentials from the Mac.
    if [[ -n "${ROOT_CNF:-}" ]]; then
        rm -f -- "$ROOT_CNF"
    fi

    # Clear password variables.
    unset ROOT_PASSWORD DOCTOR_PASSWORD NURSE_PASSWORD
    unset RECEPTION_PASSWORD ADMIN_PASSWORD
}

trap cleanup EXIT

# Check that the database container is running.
if ! docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -qx true; then
    echo "Error: hospital-db is not running."
    exit 1
fi

#Ask for a password without showing it on screen.
ask_password() {
    local label="$1"
    local password

    read -r -s -p "Enter password for $label: " password
    echo >&2

    # Restrict characters so values can safely enter SQL literals.
    if [[ ! "$password" =~ ^[A-Za-z0-9_!@#%^.*-]{8,}$ ]]; then
        echo "Error: Use at least 8 characters (letters, numbers, _!@#%^.*-)." >&2
        exit 1
    fi

    printf '%s' "$password"
}

echo "=== Hospital Security Integration ==="

read -r -s -p "Enter MariaDB root password: " ROOT_PASSWORD
echo

# Create a temporary MariaDB client configuration file.
ROOT_CNF=$(mktemp "${TMPDIR:-/tmp}/hospital-root.XXXXXX")
CONTAINER_CNF="/tmp/$(basename "$ROOT_CNF").cnf"

# Escape characters that have special meaning in option files.
if [[ "$ROOT_PASSWORD" == *$'\n'* || "$ROOT_PASSWORD" == *$'\r'* ]]; then
    echo "Error: Root password contains an unsupported newline." >&2
    exit 1
fi

ESCAPED_ROOT_PASSWORD=${ROOT_PASSWORD//\\/\\\\}
ESCAPED_ROOT_PASSWORD=${ESCAPED_ROOT_PASSWORD//\"/\\\"}

printf '[client]\npassword="%s"\n' "$ESCAPED_ROOT_PASSWORD" > "$ROOT_CNF"
unset ESCAPED_ROOT_PASSWORD

# Copy the credentials into the container with restricted permissions.
docker cp "$ROOT_CNF" "$CONTAINER:$CONTAINER_CNF"
docker exec -u root "$CONTAINER" chmod 600 "$CONTAINER_CNF"

DOCTOR_PASSWORD=$(ask_password "Doctor")
NURSE_PASSWORD=$(ask_password "Nurse")
RECEPTION_PASSWORD=$(ask_password "Receptionist")
ADMIN_PASSWORD=$(ask_password "Admin")

# Generate SQL in memory and pass it directly to MariaDB.
# Both localhost and % accounts must be configured.
{
    for HOST in localhost '%'; do
        printf "ALTER USER 'dr_test'@'%s' IDENTIFIED VIA ed25519 USING PASSWORD('%s') REQUIRE SSL;\n" "$HOST" "$DOCTOR_PASSWORD"
        printf "ALTER USER 'nurse_test'@'%s' IDENTIFIED VIA ed25519 USING PASSWORD('%s') REQUIRE SSL;\n" "$HOST" "$NURSE_PASSWORD"
        printf "ALTER USER 'reception_test'@'%s' IDENTIFIED VIA ed25519 USING PASSWORD('%s') REQUIRE SSL;\n" "$HOST" "$RECEPTION_PASSWORD"
        printf "ALTER USER 'admin_test'@'%s' IDENTIFIED VIA ed25519 USING PASSWORD('%s') REQUIRE SSL;\n" "$HOST" "$ADMIN_PASSWORD"
    done
} | docker exec -i -u root "$CONTAINER" \
    mariadb --defaults-extra-file="$CONTAINER_CNF" --batch -u root || {
        echo "ERROR: Hospital security configuration failed." >&2
        echo "Check the root password, ED25519 plugin and existing accounts." >&2
        exit 1
    }

echo "ED25519 authentication and required TLS configured successfully!"
