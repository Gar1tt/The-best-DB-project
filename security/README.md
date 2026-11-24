
# Hospital Database — Security Setup

## Overview

This part of the project handles authentication and secure connections to the hospital database using MariaDB 13.1.

We implemented ED25519 authentication and TLS encryption for four test accounts: Doctor, Nurse, Receptionist, and Admin. Each account uses its assigned database role, so users can only access the information their role allows.

We also created automated tests to verify that authentication, encryption, and access restrictions work correctly.

## 1. Requirements

Before running the security setup, make sure you have:

- Docker Desktop installed and running.
- The `hospital-db` container running.
- The hospital database and its tables imported.
- The database roles and test accounts created using `../database/02_roles_grants.sql`.

The Docker configuration loads the ED25519 authentication plugin.

## 2. Setting Up Authentication

From the main project folder, run:

    ./security/setup-hospital-users.sh

The script asks for the MariaDB root password and a password for each test account. Passwords are hidden while typing.

It configures ED25519 authentication and requires SSL connections for the following users:

| Account | Role |
|---|---|
| `dr_test` | `doctor` |
| `nurse_test` | `nurse` |
| `reception_test` | `receptionist` |
| `admin_test` | `hospital_admin` |

Both the `localhost` and `%` account definitions are configured.

The script only updates authentication and SSL requirements. Existing roles and permissions remain unchanged.

**Note:** Run this script after `../database/02_roles_grants.sql`, since that file creates the test accounts.

## 3. Running the Security Tests

To run the automated integration tests, use:

    bash security/tests/hospital-integration-tests.sh

The script asks for the four test-account passwords and runs 19 checks.

These tests verify that:

- Each account can log in with its correct role.
- Connections use verified TLS.
- Authorized database queries succeed.
- Unauthorized queries are rejected with MariaDB error 1142.
- Connections without SSL are rejected.

A successful run should end with:

    RESULTS: 19 passed, 0 failed
    All hospital integration tests passed!

We also have a separate test script for ED25519 and TLS:

    bash security/tests/run-tests.sh

This checks plugin availability, encrypted connections, certificate verification, and SSL restrictions using a temporary test account.

## 4. Security Features

### ED25519 Authentication

The test accounts use MariaDB's ED25519 authentication plugin instead of the original authentication method.

The setup script updates the accounts without changing their assigned roles.

### TLS Encryption

All four test accounts are configured with `REQUIRE SSL`, so connections without encryption are rejected.

The automated tests use `--ssl-verify-server-cert` to verify the server certificate.

### Role-Based Access

Each account has different permissions depending on its role.

For example, doctors can read and update medical records, while nurses can read those records but cannot modify them.

Receptionists can access patient contact information through a restricted view, while administrators have full access to the hospital database.

The permissions are defined in `../database/02_roles_grants.sql`.

## 5. Test Results

We tested the integration locally using MariaDB 13.1.1.

| Test | Result |
|---|---|
| ED25519 authentication | Passed |
| Verified TLS connections | Passed |
| Connections without SSL | Rejected |
| Role-based permissions | Passed |
| Automated integration tests | 19 passed, 0 failed |

All eight account definitions (`localhost` and `%` for each user) were confirmed to use ED25519 and require SSL.

## 6. Notes

This setup is intended for the university project and uses demonstration accounts with generated hospital data.

The setup script asks for passwords instead of storing them directly in the script. However, it currently passes the root password through a temporary Docker environment variable and builds SQL statements from validated password inputs. These choices are acceptable for a controlled demonstration but would require stronger credential handling in a production environment.

To reset the test accounts, run `../database/02_roles_grants.sql` again, followed by `security/setup-hospital-users.sh`.


## 7. Security Verification and Attack Tests

We tested the security configuration to confirm that the hospital accounts can perform their authorized operations while restricted operations are blocked.

### Authentication, Encryption and Authorization

The system uses three main security controls:

- **ED25519 authentication:** Verifies the identity of the database user.
- **TLS encryption:** Protects the connection between the client and MariaDB. The server requires SSL, while the client verifies the server certificate.
- **Database roles:** Control which tables and operations each user can access.

These controls work together. Successfully logging in does not automatically give a user access to every table.

### Attack Tests

We tested the following scenarios:

| Test | Expected Result | Security Control |
|---|---|---|
| Doctor connects without SSL | Login rejected | `REQUIRE SSL` |
| Nurse connects without SSL | Login rejected | `REQUIRE SSL` |
| Receptionist connects without SSL | Login rejected | `REQUIRE SSL` |
| Admin connects without SSL | Login rejected | `REQUIRE SSL` |
| Doctor attempts to read `accounts` | ERROR 1142 | Role privileges |
| Nurse attempts to read `accounts` | ERROR 1142 | Role privileges |
| Receptionist attempts to read `medical_records` | ERROR 1142 | Role privileges |
| Any hospital account uses verified TLS | Connection succeeds | TLS certificate verification |

All these scenarios passed during our local tests.

We also manually verified that nurses cannot update medical records and that receptionists only see the permitted patient information through the `patient_contact` view.

### Checking the Configuration

Connect to MariaDB as root:

    docker exec -it hospital-db mariadb -u root -p

Enter the local MariaDB root password.

To check that ED25519 is enabled:

    SELECT PLUGIN_NAME, PLUGIN_STATUS
    FROM information_schema.PLUGINS
    WHERE PLUGIN_NAME = 'ed25519';

Expected status: `ACTIVE`.

To check the authentication and SSL requirements:

    SELECT User, Host, plugin, ssl_type
    FROM mysql.user
    WHERE User IN (
        'dr_test',
        'nurse_test',
        'reception_test',
        'admin_test'
    )
    ORDER BY User, Host;

All eight account definitions should show `ed25519` as the authentication plugin and `ANY` as the SSL requirement.

To inspect the database permissions:

    SHOW GRANTS FOR doctor;
    SHOW GRANTS FOR nurse;
    SHOW GRANTS FOR receptionist;
    SHOW GRANTS FOR hospital_admin;

These commands allow the configuration to be checked independently of the automated test results.

### Automated Test Summary

The integration test script performs 19 checks across the four hospital accounts.

During local testing on MariaDB 13.1.1, all 19 checks passed with no failures.

The tests can be repeated using:

    bash security/tests/hospital-integration-tests.sh
