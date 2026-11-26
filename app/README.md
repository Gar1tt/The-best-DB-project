# Hospital Keycard Terminal

Run the [one-time setup](../README.md#start-from-a-fresh-clone) from the repository root. It creates the virtual environment and configures the local MariaDB service. The Python process runs on your machine and uses the pinned PyMySQL ED25519 dependency.

```bash
.venv/bin/python app/hospital.py --ca certs/ca.pem --user reception_test
.venv/bin/python app/hospital.py --ca certs/ca.pem --user nurse_test keycard
.venv/bin/python app/hospital.py --ca certs/ca.pem --user admin_test connection
```

The password is read from a terminal prompt, never from an app configuration file. The app verifies the server's certificate chain and hostname and displays the negotiated TLS details. For a compatible separate server, supply `--host`, `--port`, and its trusted CA file.

The same menu is visible to all users; the database enforces the [role model](../DATABASE_SETUP.md#effective-privileges). Menu option **13** reads the current trigger-generated audit entries. Follow the [demo walkthrough](../README.md#open-the-terminal-app) to compare the same operation across roles.
