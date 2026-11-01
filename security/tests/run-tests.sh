#!/bin/bash

# Hospital Database Security Tests
# Run this script from the main project folder using:
# bash security/tests/run-tests.sh
# This script checks if ED25519 and TLS are working correctly.
# It also tests insecure connections and removes temporary accounts after testing.
# Once the hospital database and application are finished,
# we will update these tests to work with the final system.
# For now, we use temporary accounts to test the security features.

set -o pipefail

echo "Starting security tests..."
echo ""

# First, check if our MariaDB container is running.
if ! docker ps --format '{{.Names}}' | grep -qx "hospital-db"; then
    echo "FAIL: MariaDB is not running."
    exit 1
fi

echo "PASS: MariaDB is running."

# Now check if ED25519 is active.
echo "Checking ED25519..."
echo "MariaDB root password:"

if docker exec -it hospital-db mariadb -u root -p \
    --batch --skip-column-names \
    -e "SELECT PLUGIN_STATUS FROM information_schema.PLUGINS WHERE PLUGIN_NAME = 'ed25519';" \
    | tr -d '\r' | grep -qx "ACTIVE"; then
    echo "PASS: ED25519 is active."
else
    echo "FAIL: ED25519 check failed."
    exit 1
fi


echo ""
echo "Checking TLS connection..."
echo "MariaDB root password:"

# Connect through TCP and require server certificate verification.
tls_version=$(docker exec -it hospital-db mariadb \
    --protocol=TCP \
    --host=127.0.0.1 \
    --ssl-verify-server-cert \
    -u root -p \
    --batch --skip-column-names \
    -e "SHOW SESSION STATUS LIKE 'Ssl_version';" \
    | tr -d '\r' | awk '$1 == "Ssl_version" {print $2}')

if [[ "$tls_version" == TLSv* ]]; then
    echo "PASS: Verified TLS connection established ($tls_version)."
else
    echo "FAIL: TLS connection could not be verified."
    exit 1
fi


echo ""
echo "Checking incorrect TLS certificate fingerprint..."
echo "MariaDB root password:"

# Try connecting with an incorrect certificate fingerprint.
# The connection should fail even with the correct password.
result=$(docker exec -it hospital-db mariadb \
    --protocol=TCP \
    --host=127.0.0.1 \
    --ssl-verify-server-cert \
    --ssl-fp=0000000000000000000000000000000000000000000000000000000000000000 \
    -u root -p \
    -e "SELECT 1;" 2>&1)

if echo "$result" | grep -q "Fingerprint validation of peer certificate failed"; then
    echo "PASS: Incorrect certificate fingerprint was rejected."
else
    echo "FAIL: Certificate fingerprint test did not give the expected error."
    echo "$result"
    exit 1
fi



echo ""
echo "Testing TLS restrictions..."

# Create a temporary account with a random password.
test_password=$(openssl rand -hex 16)

echo "Creating temporary test account..."
echo "Enter your MariaDB root password:"

if ! docker exec -it hospital-db mariadb -u root -p \
    -e "CREATE USER 'security_auto_test'@'127.0.0.1'
        IDENTIFIED VIA ed25519
        USING PASSWORD('$test_password')
        REQUIRE SSL;"; then
    echo "FAIL: Could not create test account."
    exit 1
fi

echo "PASS: Temporary account created."

# Check that the temporary account actually requires TLS.
echo "Checking the test account's TLS requirement..."
echo "MariaDB root password:"

account_settings=$(docker exec -it hospital-db mariadb -u root -p \
    --batch --skip-column-names \
    -e "SHOW CREATE USER 'security_auto_test'@'127.0.0.1';")

if echo "$account_settings" | grep -q "REQUIRE SSL"; then
    echo "PASS: Test account requires TLS."
else
    echo "FAIL: Test account does not require TLS."
    exit 1
fi

# Remove the temporary account after testing.
cleanup() {
    echo "Removing temporary test account..."

    if docker exec -it hospital-db mariadb -u root -p \
        -e "DROP USER IF EXISTS 'security_auto_test'@'127.0.0.1';"; then
        echo "PASS: Temporary test account removed."
    else
        echo "FAIL: Could not remove temporary test account."
        return 1
    fi
}
trap cleanup EXIT

# First check that the account can connect with TLS.
if docker exec -e MYSQL_PWD="$test_password" hospital-db \
    mariadb --protocol=TCP --host=127.0.0.1 \
    --ssl-verify-server-cert \
    -u security_auto_test -e "SELECT 1;" > /dev/null 2>&1; then
    echo "PASS: Secure login successful."
else
    echo "FAIL: Secure login failed."
    exit 1
fi

# Try connecting without TLS.
# The account requires SSL, so MariaDB should reject it.
error_output=$(docker exec -e MYSQL_PWD="$test_password" hospital-db \
    mariadb --protocol=TCP --host=127.0.0.1 \
    --disable-ssl \
    -u security_auto_test -e "SELECT 1;" 2>&1)

exit_code=$?

if [ "$exit_code" -ne 0 ] &&
   echo "$error_output" | grep -q "ERROR 1045"; then
    echo "PASS: Unencrypted connection rejected."
else
    echo "FAIL: Unencrypted connection test did not behave as expected."
    echo "$error_output"
    exit 1
fi

echo ""
echo "Security tests completed."
