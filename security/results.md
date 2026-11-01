
# Security Test Results

## ED25519 Authentication
MariaDB version: 13.1.1
Docker container: hospital-db

### Plugin installation
ED25519 installation: PASS - Plugin installed and verified as ACTIVE.

### Account authentication
Created a temporary account using ED25519.

Correct password: PASS - Login successful.
Incorrect password: PASS - Access denied (ERROR 1045).

The temporary account was deleted after testing it.

### Automatic plugin loading
Added the ED25519 plugin loading option to docker-compose.yml.

Tested it using a completely new MariaDB container without manually installing the plugin.

PASS - ED25519 was automatically loaded and its status was ACTIVE.

The temporary Docker container was removed after testing.

## Verified TLS

### Secure connection
Connected using the tls_test account with ED25519 authentication and TLS certificate verification enabled.

PASS - TCP connection established using TLS 1.3. The client reported "cert is OK".

### Unencrypted connection
Tried connecting with TLS disabled using an account with REQUIRE SSL.

PASS - MariaDB refused the connection.

### Incorrect certificate fingerprint
Tried connecting with an invalid certificate fingerprint.

PASS - Connection rejected with ERROR 2026: Fingerprint validation of peer certificate failed.

The temporary tls_test account was deleted after testing.

## Additional Security Testing

### Automated security tests
Created run-tests.sh to automatically check ED25519 and TLS.

The script checks if MariaDB is running, verifies that ED25519 is active, tests a TLS connection and checks that an incorrect certificate fingerprint is rejected.

PASS - All automated checks completed successfully.

### Temporary account testing
The script creates a temporary account using ED25519 and REQUIRE SSL.

Secure login: PASS - Connection accepted.
Unencrypted connection: PASS - Connection rejected.

### Automatic cleanup
The script removes the temporary account after testing.

The account deletion was also checked directly in MariaDB during testing.

## Final Integration

Status: Waiting

Once the hospital database and application are ready, we will test ED25519 authentication and verified TLS using the final application's database connector.

We will also add security tests for the hospital roles and permissions.
