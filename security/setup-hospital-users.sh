#!/usr/bin/env bash
set -euo pipefail

# Run after hospital_full.sql and database/02_roles_grants.sql.
# Configures authentication without changing the existing roles.

CONTAINER="hospital-db"

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
} | docker exec -i -e MYSQL_PWD="$ROOT_PASSWORD" "$CONTAINER" \
    mariadb --batch -u root

unset ROOT_PASSWORD DOCTOR_PASSWORD NURSE_PASSWORD RECEPTION_PASSWORD ADMIN_PASSWORD

echo "ED25519 authentication and required TLS configured successfully!"
