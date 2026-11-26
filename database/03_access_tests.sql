-- Optional read-only inventory for a freshly provisioned demo. Run as root.
-- For the actual role checks, use: python3 security/demo.py verify

SELECT VERSION() AS mariadb_version, @@require_secure_transport AS requires_secure_transport;

SELECT User, Host, plugin, ssl_type
FROM mysql.user
WHERE User IN ('dr_test', 'nurse_test', 'reception_test', 'admin_test')
ORDER BY User, Host;

SHOW GRANTS FOR hospital_staff;
SHOW GRANTS FOR doctor;
SHOW GRANTS FOR nurse;
SHOW GRANTS FOR receptionist;
SHOW GRANTS FOR hospital_admin;

SELECT TRIGGER_NAME, EVENT_MANIPULATION, EVENT_OBJECT_TABLE, DEFINER
FROM information_schema.TRIGGERS
WHERE TRIGGER_SCHEMA = 'hospital'
ORDER BY TRIGGER_NAME;
