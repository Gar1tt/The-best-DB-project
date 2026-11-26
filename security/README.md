# Security setup

Use `python3 security/demo.py setup` on an empty local demo, or `python3 security/demo.py verify` to re-check an existing demo without writing sample rows. Follow the [main setup instructions](../README.md#start-from-a-fresh-clone) for prerequisites, secrets, and expected results. The prior shell scripts are compatibility entry points to the current workflow.

## Provisioning

- **Database:** The Compose build pins MariaDB's upstream 13.1.2 Dockerfile. Root is limited to the local database account and provisioning connects through the container's socket. The published port is bound to host loopback.
- **Accounts:** The bootstrap creates the four account definitions directly with ED25519 and `REQUIRE SSL`. It assigns and activates each role before unlocking the accounts. Staff passwords are neither stored in a file by the bootstrap nor passed as process arguments. `.env` holds a local MariaDB root password for Compose; protect it and never commit it.
- **TLS:** The bootstrap creates a demo CA and verifies the server certificate for `127.0.0.1`. Only the server key and public certificates are copied into the database volume. The final Compose configuration also requires secure transport. The app requires a trusted CA and verifies the hostname or IP.
- **Authorization:** MariaDB roles, explicit `DENY` rules, and limited definer views enforce permissions. The application does not use root or change privileges. See the [effective privilege matrix](../DATABASE_SETUP.md#effective-privileges).

## Verification

The verifier exercises the app's connection code with all four roles, checks refusal of incorrect credentials, no TLS, an unrelated CA and a certificate hostname mismatch, and checks representative allowed and refused operations for the major permission boundaries. Fresh setup also exercises normal app writes and reads their server-generated audit events as the admin.

Expected permission or authentication refusals are distinguished from infrastructure errors. The verifier does not change role grants. See [verification notes](results.md) for the most recent run and the scope of the evidence.
