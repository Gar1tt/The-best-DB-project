#!/usr/bin/env python3
"""Hospital keycard terminal.

A small terminal application for the hospital database. Your database login
is your keycard: every door of the hospital is on the menu for everybody, and
the database decides which doors open. The application itself contains no
"who may do what" rules, so a changed or hostile copy of it gains nothing.

Run it from the project folder:

    python app/hospital.py --ca certs/ca.pem          (menu)
    python app/hospital.py --ca certs/ca.pem keycard  (print the keycard)

The password is asked on the terminal. It is not read from a file, an option
or an environment variable.
"""

import argparse
import datetime
import getpass
import sys
import warnings

import pymysql

import secure_connect

# MariaDB errors that mean "you have no right to do this"
# (no access to the database, to the table, to the column).
DENIED = (1044, 1142, 1143)

# The doors: table or view and what is behind it.
DOORS = [
    ("patients", "patient register with insurance numbers"),
    ("patient_contact", "patient contact view; no insurance numbers"),
    ("medical_records", "diagnoses and notes"),
    ("appointments", "appointments"),
    ("staff", "staff records with e-mail and hire date"),
    ("staff_directory", "staff view; no e-mail or hire date"),
    ("departments", "departments"),
    ("roles", "job roles"),
    ("accounts", "staff logins"),
    ("audit_log", "login history"),
]

class Session:
    def __init__(self, host, port, user, password, ca_file):
        self.host, self.port = host, port
        self.connection = secure_connect.connect(host, port, user, password, ca_file)
        try:
            _, rows, _ = self.query("SELECT CURRENT_USER(), CURRENT_ROLE()")
            self.account, self.role = rows[0]
            self.tls, self.cipher = (
                self.query("SHOW SESSION STATUS LIKE %s", (name,))[1][0][1]
                for name in ("Ssl_version", "Ssl_cipher")
            )
            if not self.tls or not self.cipher:
                raise secure_connect.ServerIdentityError("no TLS session was negotiated")
        except Exception:
            self.connection.close()
            raise

    def query(self, sql, args=None):
        """Run one statement. Values in args are escaped by the driver."""
        with self.connection.cursor() as cursor:
            cursor.execute(sql, args)
            headers = [column[0] for column in cursor.description or ()]
            return headers, cursor.fetchall(), cursor.lastrowid


# ---------------------------------------------------------------- output

def table(headers, rows, width=44):
    if not rows:
        print("  (no rows)")
        return
    cells = [["" if value is None else "".join(c if c.isprintable() else " "
                                              for c in str(value)) for value in row]
             for row in rows]
    cells = [[text if len(text) <= width else text[:width - 3] + "..." for text in row]
             for row in cells]
    sizes = [max(len(headers[i]), max(len(row[i]) for row in cells))
             for i in range(len(headers))]
    line = "  " + "  ".join("{:<%d}" % size for size in sizes)
    print(line.format(*headers).rstrip())
    print(line.format(*["-" * size for size in sizes]))
    for row in cells:
        print(line.format(*row).rstrip())


def ask(prompt):
    return input("  " + prompt + ": ").strip()


def ask_number(prompt):
    text = ask(prompt)
    if not text.isascii() or not text.isdigit() or int(text) < 1:
        raise ValueError("enter a positive whole number")
    return int(text)


# ---------------------------------------------------------------- keycard

def read_keycard(session):
    """Check read access without retrieving any rows or changing the database."""
    doors = []
    for name, description in DOORS:
        try:
            # Object names are fixed above; no user input is used as an identifier.
            session.query(f"SELECT 1 FROM `{name}` LIMIT 0")
        except pymysql.MySQLError as error:
            if error.args[0] not in DENIED:
                raise
            doors.append((name, "LOCKED", description))
        else:
            doors.append((name, "OPEN", description))
    return doors


def keycard(session):
    print("  KEYCARD of %s, role %s" % (session.account, session.role))
    print("  Read access checked by MariaDB just now; no rows retrieved.\n")
    table(["door", "read access", "behind it"], read_keycard(session))


# ---------------------------------------------------------------- doors

PATIENT_COLUMNS = ["patient_id", "first_name", "last_name", "birth_date", "phone", "address"]


def search_patients(session, text):
    """Patients whose first or last name contains text (at most 20)."""
    return session.query(
        "SELECT " + ", ".join(PATIENT_COLUMNS) + " FROM patient_contact "
        "WHERE first_name LIKE %s OR last_name LIKE %s "
        "ORDER BY last_name, first_name LIMIT 20",
        ("%" + text + "%", "%" + text + "%"))[1]


def find_patient(session):
    table(PATIENT_COLUMNS, search_patients(session, ask("Name or part of a name")))


def insurance(session):
    headers, rows, _ = session.query(
        "SELECT patient_id, first_name, last_name, insurance_no "
        "FROM patients WHERE patient_id = %s", (ask_number("Patient id"),))
    table(headers, rows)


def medical_file(session):
    headers, rows, _ = session.query(
        "SELECT record_id, record_date, diagnosis, staff_id, notes "
        "FROM medical_records WHERE patient_id = %s ORDER BY record_date DESC LIMIT 20",
        (ask_number("Patient id"),))
    table(headers, rows)


def add_diagnosis(session):
    patient, staff = ask_number("Patient id"), ask_number("Treating staff id")
    diagnosis, notes = ask("Diagnosis"), ask("Notes")
    if not diagnosis:
        raise ValueError("diagnosis cannot be empty")
    if ask("Save this diagnosis? [y/N]").lower() != "y":
        return
    record = session.query(
        "INSERT INTO medical_records (patient_id, staff_id, diagnosis, notes, record_date) "
        "VALUES (%s, %s, %s, %s, CURDATE())", (patient, staff, diagnosis, notes))[2]
    print("  Saved as medical record %d." % record)


def appointments(session):
    headers, rows, _ = session.query(
        "SELECT appointment_id, appointment_date, staff_id, status "
        "FROM appointments WHERE patient_id = %s ORDER BY appointment_date DESC LIMIT 20",
        (ask_number("Patient id"),))
    table(headers, rows)


def book_appointment(session):
    patient, staff = ask_number("Patient id"), ask_number("Staff id")
    when = datetime.datetime.strptime(ask("Date and time (YYYY-MM-DD HH:MM)"),
                                      "%Y-%m-%d %H:%M")
    if ask("Book this appointment? [y/N]").lower() != "y":
        return
    number = session.query(
        "INSERT INTO appointments (patient_id, staff_id, appointment_date, status) "
        "VALUES (%s, %s, %s, 'Scheduled')", (patient, staff, when))[2]
    print("  Booked as appointment %d." % number)


def change_phone(session):
    patient, phone = ask_number("Patient id"), ask("New phone number")
    if not phone:
        raise ValueError("phone number cannot be empty")
    if ask("Save this phone number? [y/N]").lower() != "y":
        return
    session.query("UPDATE patient_contact SET phone = %s WHERE patient_id = %s",
                  (phone, patient))
    headers, rows, _ = session.query(
        "SELECT patient_id, first_name, last_name, phone FROM patient_contact "
        "WHERE patient_id = %s", (patient,))
    table(headers, rows)


def staff_directory(session):
    headers, rows, _ = session.query(
        "SELECT s.staff_id, s.first_name, s.last_name, r.role_name, d.name AS department "
        "FROM staff_directory s LEFT JOIN roles r ON r.role_id = s.role_id "
        "LEFT JOIN departments d ON d.dept_id = s.dept_id ORDER BY s.staff_id")
    table(headers, rows)


def login_history(session):
    headers, rows, _ = session.query(
        "SELECT log_id, account_id, action, action_time, ip_address "
        "FROM audit_log ORDER BY action_time DESC, log_id DESC LIMIT 10")
    table(headers, rows)


def staff_logins(session):
    headers, rows, _ = session.query(
        "SELECT account_id, staff_id, username, is_active, last_login "
        "FROM accounts ORDER BY account_id LIMIT 10")
    table(headers, rows)


def connection_details(session):
    print("  Signed in as     %s, role %s" % (session.account, session.role))
    print("  Server           %s:%d" % (session.host, session.port))
    print("  Encryption       %s, %s" % (session.tls, session.cipher))
    print("  Server identity  verified against the supplied CA and host")


MENU = [
    ("My keycard: what can I read?", keycard),
    ("Find a patient", find_patient),
    ("Insurance number of a patient", insurance),
    ("Medical file of a patient", medical_file),
    ("Add a diagnosis", add_diagnosis),
    ("Appointments of a patient", appointments),
    ("Book an appointment", book_appointment),
    ("Change a patient's phone number", change_phone),
    ("Staff directory", staff_directory),
    ("Login history (audit log)", login_history),
    ("Staff logins (accounts)", staff_logins),
    ("Connection details", connection_details),
]
COMMANDS = {"keycard": keycard, "connection": connection_details}


def open_door(session, action):
    """Run one menu entry and report what the database answered."""
    try:
        return action(session)
    except pymysql.MySQLError as error:
        code, message = error.args[0], error.args[-1]
        if code in DENIED:
            print("  LOCKED by the database: %s (error %d)" % (message, code))
        else:
            print("  The database reported: %s (error %s)" % (message, code))
    except ValueError as error:
        print("  Not done: %s" % error)
    return 1


def menu(session):
    while True:
        print()
        for number, (title, _) in enumerate(MENU, 1):
            print("  %2d  %s" % (number, title))
        print("   0  Leave")
        try:
            choice = ask("Door")
        except (EOFError, KeyboardInterrupt):
            print()
            return
        if choice == "0":
            return
        if choice.isascii() and choice.isdigit() and len(choice) <= 2 and 1 <= int(choice) <= len(MENU):
            print()
            try:
                open_door(session, MENU[int(choice) - 1][1])
            except (EOFError, KeyboardInterrupt):
                print()
        else:
            print("  Please type a number from the list.")


def main():
    parser = argparse.ArgumentParser(description="Hospital keycard terminal")
    parser.add_argument("command", nargs="?", choices=sorted(COMMANDS),
                        help="run one command and exit instead of showing the menu")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=3306)
    parser.add_argument("--ca", required=True, help="trusted CA certificate in PEM format")
    parser.add_argument("--user", choices=("dr_test", "nurse_test", "reception_test",
                                           "admin_test"), help="hospital demo account")
    options = parser.parse_args()

    print("+------------------------------------------------------------+")
    print("|  HOSPITAL KEYCARD TERMINAL                                 |")
    print("|  Every door is on the menu. The database decides which     |")
    print("|  doors open for you.                                       |")
    print("+------------------------------------------------------------+")
    try:
        user = options.user or input("Staff login: ").strip()
        if user not in ("dr_test", "nurse_test", "reception_test", "admin_test"):
            parser.error("choose one of the four hospital demo accounts")
        with warnings.catch_warnings():
            warnings.simplefilter("error", getpass.GetPassWarning)
            password = getpass.getpass("Password: ")
    except getpass.GetPassWarning:
        print("A terminal with hidden password input is required.", file=sys.stderr)
        return 2
    except (EOFError, KeyboardInterrupt):
        print()
        return 1

    try:
        session = Session(options.host, options.port, user, password, options.ca)
    except (secure_connect.ServerIdentityError, OSError) as error:
        print("Connection stopped: %s." % error)
        return 2
    except pymysql.MySQLError as error:
        print("Login refused: %s" % error.args[-1])
        return 1
    finally:
        del password

    print()
    try:
        if options.command != "connection":
            connection_details(session)
        if options.command:
            print()
            return 1 if open_door(session, COMMANDS[options.command]) else 0
        menu(session)
        return 0
    finally:
        session.connection.close()


if __name__ == "__main__":
    sys.exit(main())
