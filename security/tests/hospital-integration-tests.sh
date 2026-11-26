
#!/usr/bin/env bash
set -euo pipefail

# Hospital Security Integration Tests
# Run after setup-hospital-users.sh.
# Tests authentication, TLS and role permissions.
# All SQL checks are read-only.

CONTAINER="${HOSPITAL_DB_CONTAINER:-hospital-db}"
PASSED=0
FAILED=0

pass() {
    echo "PASS: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo "FAIL: $1"
    FAILED=$((FAILED + 1))
}

# Connect using verified TLS.
secure_query() {
    local username="$1"
    local password="$2"
    local query="$3"

    docker exec -e MYSQL_PWD="$password" "$CONTAINER" \
        mariadb --protocol=TCP \
        --host=127.0.0.1 \
        --ssl-verify-server-cert \
        --batch --skip-column-names \
        -u "$username" hospital -e "$query"
}

# Check that a query is allowed.
test_allowed() {
    local username="$1"
    local password="$2"
    local query="$3"

    if secure_query "$username" "$password" "$query" >/dev/null; then
        pass "$username: allowed query"
    else
        fail "$username: allowed query"
    fi
}

# Check that an unauthorized query is rejected.
test_denied() {
    local username="$1"
    local password="$2"
    local query="$3"
    local output

    if output=$(secure_query "$username" "$password" "$query" 2>&1); then
        fail "$username: unauthorized query was allowed"
    elif [[ "$output" == *"ERROR 1142"* ]]; then
        pass "$username: access denied (ERROR 1142)"
    else
        fail "$username: unexpected error instead of permission denial"
    fi

}

# Verify the expected database role.
test_role() {
    local username="$1"
    local password="$2"
    local expected="$3"
    local actual

    if actual=$(secure_query "$username" "$password" \
        "SELECT CURRENT_ROLE();") && [[ "$actual" == "$expected" ]]; then
        pass "$username: correct role ($expected)"
    else
        fail "$username: incorrect role or login failed"
    fi
}

# Verify TLS is negotiated successfully.
test_tls() {
    local username="$1"
    local password="$2"
    local version

    if version=$(secure_query "$username" "$password" \
        "SHOW SESSION STATUS LIKE 'Ssl_version';") &&
        [[ "$version" == *TLSv* ]]; then
        pass "$username: verified TLS connection"
    else
        fail "$username: TLS verification failed"
    fi
}

# Verify that disabling SSL prevents login.
test_no_ssl() {
    local username="$1"
    local password="$2"

    if docker exec -e MYSQL_PWD="$password" "$CONTAINER" \
        mariadb --protocol=TCP \
        --host=127.0.0.1 \
        --disable-ssl \
        -u "$username" hospital \
        -e "SELECT 1;" >/dev/null 2>&1; then
        fail "$username: unencrypted login was allowed"
    else
        pass "$username: unencrypted login rejected"
    fi
}

echo "===================================="
echo " Hospital Security Integration Tests"
echo "===================================="

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "ERROR: hospital-db is not running."
    exit 1
fi

echo
echo "Enter the test passwords."
echo "Input will be hidden."

read -r -s -p "Doctor password: " DOCTOR_PASSWORD
echo
read -r -s -p "Nurse password: " NURSE_PASSWORD
echo
read -r -s -p "Receptionist password: " RECEPTION_PASSWORD
echo
read -r -s -p "Admin password: " ADMIN_PASSWORD
echo

echo
echo "=== Testing Doctor ==="
test_role dr_test "$DOCTOR_PASSWORD" doctor
test_tls dr_test "$DOCTOR_PASSWORD"
test_allowed dr_test "$DOCTOR_PASSWORD" \
    "SELECT * FROM medical_records LIMIT 1;"
test_denied dr_test "$DOCTOR_PASSWORD" \
    "SELECT * FROM accounts LIMIT 1;"
test_no_ssl dr_test "$DOCTOR_PASSWORD"

echo
echo "=== Testing Nurse ==="
test_role nurse_test "$NURSE_PASSWORD" nurse
test_tls nurse_test "$NURSE_PASSWORD"
test_allowed nurse_test "$NURSE_PASSWORD" \
    "SELECT * FROM medical_records LIMIT 1;"
test_denied nurse_test "$NURSE_PASSWORD" \
    "SELECT * FROM accounts LIMIT 1;"
test_no_ssl nurse_test "$NURSE_PASSWORD"

echo
echo "=== Testing Receptionist ==="
test_role reception_test "$RECEPTION_PASSWORD" receptionist
test_tls reception_test "$RECEPTION_PASSWORD"
test_allowed reception_test "$RECEPTION_PASSWORD" \
    "SELECT * FROM patient_contact LIMIT 1;"
test_denied reception_test "$RECEPTION_PASSWORD" \
    "SELECT * FROM medical_records LIMIT 1;"
test_no_ssl reception_test "$RECEPTION_PASSWORD"

echo
echo "=== Testing Admin ==="
test_role admin_test "$ADMIN_PASSWORD" hospital_admin
test_tls admin_test "$ADMIN_PASSWORD"
test_allowed admin_test "$ADMIN_PASSWORD" \
    "SELECT * FROM accounts LIMIT 1;"
test_no_ssl admin_test "$ADMIN_PASSWORD"

unset DOCTOR_PASSWORD NURSE_PASSWORD RECEPTION_PASSWORD ADMIN_PASSWORD

echo
echo "===================================="
echo " RESULTS: $PASSED passed, $FAILED failed"
echo "===================================="

if [[ "$FAILED" -gt 0 ]]; then
    exit 1
fi

echo "All hospital integration tests passed!"
