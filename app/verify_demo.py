"""Local acceptance checks for the configured hospital app and demo accounts."""

import argparse
from contextlib import ExitStack, redirect_stdout
import io
from pathlib import Path
import secrets
import socket
import ssl
import subprocess
import sys
import tempfile
from unittest.mock import patch

import pymysql

import hospital


ROLES = {
    "dr_test": "doctor",
    "nurse_test": "nurse",
    "reception_test": "receptionist",
    "admin_test": "hospital_admin",
}


def require(condition, detail):
    if not condition:
        raise RuntimeError(detail)


def report(detail):
    print(f"PASS: {detail}", flush=True)


def refused(session, sql, codes=(1142, 1143)):
    try:
        session.query(sql)
    except pymysql.MySQLError as error:
        require(error.args[0] in codes, f"Expected permission refusal, got {error.args[0]}")
    else:
        raise RuntimeError("Expected permission refusal, but the statement succeeded")


def menu_action(session, action, answers=()):
    out = io.StringIO()
    with patch("builtins.input", side_effect=answers), redirect_stdout(out):
        status = hospital.open_door(session, action)
    return status, out.getvalue()


def connection_refused(label, connect, expected):
    try:
        connection = connect()
    except pymysql.MySQLError as error:
        require(expected(error), f"{label}: wrong failure ({error.args[0]})")
    else:
        connection.close()
        raise RuntimeError(f"{label}: connection unexpectedly accepted")
    report(label)


def committed_writes(doctor, nurse, reception, admin):
    _, rows, _ = admin.query("SELECT COALESCE(MAX(event_id),0) FROM hospital_audit.events")
    before = rows[0][0]
    # If the scheduling role ever accidentally gains write access to charts,
    # the check fails and rolls that action back.
    nurse.connection.begin()
    try:
        status, text = menu_action(nurse, hospital.add_diagnosis, ("1", "1", "Demo", "", "y"))
        require(status == 1 and "LOCKED by the database" in text, "Nurse diagnosis write was not refused")
    finally:
        nurse.connection.rollback()
    report("the app refuses the diagnosis workflow as nurse")

    _, text = menu_action(doctor, hospital.add_diagnosis, ("1", "1", "Demo check", "", "y"))
    require("Saved as medical record" in text, "Doctor could not save a diagnosis")
    _, text = menu_action(nurse, hospital.book_appointment, ("1", "1", "2030-01-15 09:00", "y"))
    require("Booked as appointment" in text, "Nurse could not book an appointment")

    _, rows, _ = reception.query("SELECT phone FROM patient_contact WHERE patient_id = %s", (1,))
    original = rows[0][0]
    demo_phone = "555-0139" if original != "555-0139" else "555-0140"
    try:
        status, text = menu_action(reception, hospital.change_phone, ("1", demo_phone, "y"))
        require(status is None and demo_phone in text, "Reception could not save phone number")
    finally:
        reception.query("UPDATE patient_contact SET phone = %s WHERE patient_id = %s", (original, 1))

    _, events, _ = admin.query(
        "SELECT actor, action_name FROM hospital_audit.events WHERE event_id > %s", (before,)
    )
    actual = {(actor.split("@", 1)[0], action_name) for actor, action_name in events}
    require({
        ("dr_test", "DIAGNOSIS_ADDED"),
        ("nurse_test", "APPOINTMENT_BOOKED"),
        ("reception_test", "PATIENT_PHONE_CHANGED"),
    } <= actual, "Expected audit events were not written with the correct actors")
    report("successful app writes produced live server-side audit events attributed to each login")


def verify(port, ca, passwords, write_demo):
    host = "127.0.0.1"  # acceptance runner always uses the local demo
    with ExitStack() as stack:
        sessions = {}
        for user, role in ROLES.items():
            session = hospital.Session(host, port, user, passwords[user], ca)
            stack.callback(session.connection.close)
            sessions[user] = session
            require(session.account == f"{user}@%" and session.role == role,
                    f"Unexpected authenticated account or role for {user}")
            _, result, _ = session.query("SELECT VERSION()")
            require(result[0][0].startswith("13.1.2-MariaDB"), "Expected MariaDB 13.1.2")
            report(f"{user} / {role}: verified {session.tls}, {session.cipher}; {result[0][0]}")

        doctor, nurse, reception, admin = (sessions[name] for name in ROLES)
        with tempfile.TemporaryDirectory() as directory:
            unrelated_ca = str(Path(directory) / "ca.pem")
            subprocess.run(
                ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                 "-subj", "/CN=Unrelated Demo CA", "-keyout", str(Path(directory) / "ca.key"),
                 "-out", unrelated_ca], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            connection_refused(
                "Python client rejects an unrelated CA",
                lambda: hospital.Session(host, port, "dr_test", passwords["dr_test"], unrelated_ca).connection,
                lambda error: isinstance(getattr(error, "original_exception", None), ssl.SSLCertVerificationError),
            )
        resolve = socket.getaddrinfo
        with patch("socket.getaddrinfo", side_effect=lambda name, *args, **kwargs: resolve(host, *args, **kwargs)):
            connection_refused(
                "Python client rejects a hostname that is not on the certificate",
                lambda: hospital.Session("wrong.demo.invalid", port, "dr_test", passwords["dr_test"], ca).connection,
                lambda error: isinstance(getattr(error, "original_exception", None), ssl.SSLCertVerificationError)
                and error.original_exception.verify_code == 62,
            )
        connection_refused(
            "MariaDB rejects an incorrect ED25519 password",
            lambda: hospital.Session(host, port, "dr_test", secrets.token_hex(24), ca).connection,
            lambda error: error.args[0] == 1045,
        )
        connection_refused(
            "MariaDB rejects the same valid account when TLS is disabled",
            lambda: pymysql.connect(host=host, port=port, user="dr_test", password=passwords["dr_test"],
                                    database="hospital", ssl_disabled=True, connect_timeout=5, read_timeout=5),
            lambda error: error.args[0] in (1045, 3159),
        )

        status, text = menu_action(reception, hospital.find_patient, ("",))
        require(status is None and "patient_id" in text, "Reception contact view did not open")
        status, text = menu_action(reception, hospital.insurance, ("1",))
        require(status == 1 and "LOCKED by the database" in text, "Reception insurance was not refused")
        report("reception can use the app contact view, not the insurance lookup")

        doctor.query("SELECT diagnosis FROM medical_records LIMIT 0")
        refused(nurse, "SELECT diagnosis FROM medical_records LIMIT 0")
        reception.query("SELECT birth_date FROM patient_contact LIMIT 0")
        refused(nurse, "SELECT birth_date FROM patient_contact LIMIT 0")
        nurse.query("SELECT phone FROM patient_contact LIMIT 0")
        report("the nurse's column DENY overrides the inherited contact view grant")

        # 1356 is also expected here: the locked view owner itself has only
        # phone-column UPDATE. The real phone write is separately checked below.
        reception.query("UPDATE patient_contact SET phone = phone WHERE FALSE")
        refused(reception, "UPDATE patient_contact SET address = address WHERE FALSE", (1142, 1143, 1356))
        report("reception cannot change the address through the phone-only update view grant")

        admin.query("SELECT event_id FROM hospital_audit.events LIMIT 0")
        refused(admin, "UPDATE hospital_audit.events SET object_id = object_id WHERE FALSE")
        refused(nurse, "SELECT event_id FROM hospital_audit.events LIMIT 0", (1044, 1142, 1143))
        report("admin reads live audit events but cannot change them; staff cannot read them")
        if write_demo:
            committed_writes(doctor, nurse, reception, admin)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ca", required=True)
    parser.add_argument("--port", type=int, default=3306)
    parser.add_argument("--write-demo", action="store_true", help="write sample rows on a fresh demo")
    args = parser.parse_args()
    passwords = dict(zip(ROLES, (sys.stdin.readline().rstrip("\n") for _ in ROLES)))
    if not all(passwords.values()):
        parser.error("use the security/demo.py entry point to supply credentials")
    try:
        verify(args.port, args.ca, passwords, args.write_demo)
    except (RuntimeError, pymysql.MySQLError, OSError, subprocess.CalledProcessError,
            hospital.secure_connect.ServerIdentityError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print("PASS: all selected app and database checks")
    return 0


if __name__ == "__main__":
    sys.exit(main())
