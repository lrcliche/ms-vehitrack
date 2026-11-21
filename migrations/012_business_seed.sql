-- Vehitrack Empresarial | Migration 012 | Initial reference data and RBAC
-- Requires 011_business_model.sql.
-- Proposed defaults: review access policy before enabling real accounts.
-- Safe to rerun: stable codes and conflict handling.
BEGIN;

INSERT INTO business.dictionary (code, name) VALUES ('identification_type', 'Identification type')
ON CONFLICT (code) DO NOTHING;

INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'nit', 'Tax identification number', 1 FROM business.dictionary d WHERE d.code = 'identification_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'citizenship_id', 'Citizenship identification', 2 FROM business.dictionary d WHERE d.code = 'identification_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'foreign_id', 'Foreign identification', 3 FROM business.dictionary d WHERE d.code = 'identification_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'passport', 'Passport', 4 FROM business.dictionary d WHERE d.code = 'identification_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;

INSERT INTO business.dictionary (code, name) VALUES ('tax_regime', 'Tax regime')
ON CONFLICT (code) DO NOTHING;

INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'ordinary', 'Ordinary regime', 1 FROM business.dictionary d WHERE d.code = 'tax_regime'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'simple', 'Simple taxation regime', 2 FROM business.dictionary d WHERE d.code = 'tax_regime'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'not_applicable', 'Not applicable', 3 FROM business.dictionary d WHERE d.code = 'tax_regime'
ON CONFLICT (dictionary_id, code) DO NOTHING;

INSERT INTO business.dictionary (code, name) VALUES ('company_document_type', 'Company document type')
ON CONFLICT (code) DO NOTHING;

INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'tax_registration', 'Tax registration', 1 FROM business.dictionary d WHERE d.code = 'company_document_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'chamber_of_commerce', 'Chamber of commerce certificate', 2 FROM business.dictionary d WHERE d.code = 'company_document_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'legal_representation', 'Legal representation document', 3 FROM business.dictionary d WHERE d.code = 'company_document_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'operating_license', 'Operating license', 4 FROM business.dictionary d WHERE d.code = 'company_document_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'other', 'Other', 5 FROM business.dictionary d WHERE d.code = 'company_document_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;

INSERT INTO business.dictionary (code, name) VALUES ('vehicle_type', 'Vehicle type')
ON CONFLICT (code) DO NOTHING;

INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'sedan', 'Sedan', 1 FROM business.dictionary d WHERE d.code = 'vehicle_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'suv', 'SUV', 2 FROM business.dictionary d WHERE d.code = 'vehicle_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'van', 'Van', 3 FROM business.dictionary d WHERE d.code = 'vehicle_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'minibus', 'Minibus', 4 FROM business.dictionary d WHERE d.code = 'vehicle_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'bus', 'Bus', 5 FROM business.dictionary d WHERE d.code = 'vehicle_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'other', 'Other', 6 FROM business.dictionary d WHERE d.code = 'vehicle_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;

INSERT INTO business.dictionary (code, name) VALUES ('vehicle_document_type', 'Vehicle document type')
ON CONFLICT (code) DO NOTHING;

INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'registration', 'Vehicle registration', 1 FROM business.dictionary d WHERE d.code = 'vehicle_document_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'soat', 'Mandatory traffic insurance', 2 FROM business.dictionary d WHERE d.code = 'vehicle_document_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'technical_inspection', 'Technical inspection', 3 FROM business.dictionary d WHERE d.code = 'vehicle_document_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'operating_card', 'Operating card', 4 FROM business.dictionary d WHERE d.code = 'vehicle_document_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'other', 'Other', 5 FROM business.dictionary d WHERE d.code = 'vehicle_document_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;

INSERT INTO business.dictionary (code, name) VALUES ('driver_document_type', 'Driver document type')
ON CONFLICT (code) DO NOTHING;

INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'identification', 'Identification document', 1 FROM business.dictionary d WHERE d.code = 'driver_document_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'driving_license', 'Driving license', 2 FROM business.dictionary d WHERE d.code = 'driver_document_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'medical_certificate', 'Medical certificate', 3 FROM business.dictionary d WHERE d.code = 'driver_document_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'other', 'Other', 4 FROM business.dictionary d WHERE d.code = 'driver_document_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;

INSERT INTO business.dictionary (code, name) VALUES ('vehicle_expense_type', 'Vehicle expense type')
ON CONFLICT (code) DO NOTHING;

INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'fuel', 'Fuel', 1 FROM business.dictionary d WHERE d.code = 'vehicle_expense_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'maintenance', 'Maintenance', 2 FROM business.dictionary d WHERE d.code = 'vehicle_expense_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'insurance', 'Insurance', 3 FROM business.dictionary d WHERE d.code = 'vehicle_expense_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'tax', 'Tax', 4 FROM business.dictionary d WHERE d.code = 'vehicle_expense_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'parking', 'Parking', 5 FROM business.dictionary d WHERE d.code = 'vehicle_expense_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'toll', 'Toll', 6 FROM business.dictionary d WHERE d.code = 'vehicle_expense_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;
INSERT INTO business.dictionary_value (dictionary_id, code, name, sort_order)
SELECT d.id, 'other', 'Other', 7 FROM business.dictionary d WHERE d.code = 'vehicle_expense_type'
ON CONFLICT (dictionary_id, code) DO NOTHING;

-- Global roles (tenant_id IS NULL).
-- The role table uses a partial unique index; ON CONFLICT is handled by NOT EXISTS.
INSERT INTO business.role (tenant_id, code, name, description)
SELECT NULL, 'super_admin', 'Super administrator', 'Platform-wide administrative role; application must restrict assignment'
WHERE NOT EXISTS (SELECT 1 FROM business.role WHERE tenant_id IS NULL AND code = 'super_admin');
INSERT INTO business.role (tenant_id, code, name, description)
SELECT NULL, 'company_admin', 'Company administrator', 'Company administration and users'
WHERE NOT EXISTS (SELECT 1 FROM business.role WHERE tenant_id IS NULL AND code = 'company_admin');
INSERT INTO business.role (tenant_id, code, name, description)
SELECT NULL, 'manager', 'Operations manager', 'Fleet, services and reporting'
WHERE NOT EXISTS (SELECT 1 FROM business.role WHERE tenant_id IS NULL AND code = 'manager');
INSERT INTO business.role (tenant_id, code, name, description)
SELECT NULL, 'dispatcher', 'Dispatcher', 'Service requests and assignments'
WHERE NOT EXISTS (SELECT 1 FROM business.role WHERE tenant_id IS NULL AND code = 'dispatcher');
INSERT INTO business.role (tenant_id, code, name, description)
SELECT NULL, 'supervisor', 'Supervisor', 'Read operations and update operational records'
WHERE NOT EXISTS (SELECT 1 FROM business.role WHERE tenant_id IS NULL AND code = 'supervisor');
INSERT INTO business.role (tenant_id, code, name, description)
SELECT NULL, 'driver', 'Driver', 'Own assigned services'
WHERE NOT EXISTS (SELECT 1 FROM business.role WHERE tenant_id IS NULL AND code = 'driver');
INSERT INTO business.role (tenant_id, code, name, description)
SELECT NULL, 'viewer', 'Viewer', 'Read-only business access'
WHERE NOT EXISTS (SELECT 1 FROM business.role WHERE tenant_id IS NULL AND code = 'viewer');

-- Permission catalog.
INSERT INTO business.permission (code, description) VALUES ('company.read', 'company.read') ON CONFLICT (code) DO NOTHING;
INSERT INTO business.permission (code, description) VALUES ('company.write', 'company.write') ON CONFLICT (code) DO NOTHING;
INSERT INTO business.permission (code, description) VALUES ('users.read', 'users.read') ON CONFLICT (code) DO NOTHING;
INSERT INTO business.permission (code, description) VALUES ('users.write', 'users.write') ON CONFLICT (code) DO NOTHING;
INSERT INTO business.permission (code, description) VALUES ('users.assign_roles', 'users.assign_roles') ON CONFLICT (code) DO NOTHING;
INSERT INTO business.permission (code, description) VALUES ('roles.read', 'roles.read') ON CONFLICT (code) DO NOTHING;
INSERT INTO business.permission (code, description) VALUES ('roles.write', 'roles.write') ON CONFLICT (code) DO NOTHING;
INSERT INTO business.permission (code, description) VALUES ('fleet.read', 'fleet.read') ON CONFLICT (code) DO NOTHING;
INSERT INTO business.permission (code, description) VALUES ('fleet.write', 'fleet.write') ON CONFLICT (code) DO NOTHING;
INSERT INTO business.permission (code, description) VALUES ('drivers.read', 'drivers.read') ON CONFLICT (code) DO NOTHING;
INSERT INTO business.permission (code, description) VALUES ('drivers.write', 'drivers.write') ON CONFLICT (code) DO NOTHING;
INSERT INTO business.permission (code, description) VALUES ('customers.read', 'customers.read') ON CONFLICT (code) DO NOTHING;
INSERT INTO business.permission (code, description) VALUES ('customers.write', 'customers.write') ON CONFLICT (code) DO NOTHING;
INSERT INTO business.permission (code, description) VALUES ('services.read', 'services.read') ON CONFLICT (code) DO NOTHING;
INSERT INTO business.permission (code, description) VALUES ('services.write', 'services.write') ON CONFLICT (code) DO NOTHING;
INSERT INTO business.permission (code, description) VALUES ('services.assign', 'services.assign') ON CONFLICT (code) DO NOTHING;
INSERT INTO business.permission (code, description) VALUES ('services.close', 'services.close') ON CONFLICT (code) DO NOTHING;
INSERT INTO business.permission (code, description) VALUES ('expenses.read', 'expenses.read') ON CONFLICT (code) DO NOTHING;
INSERT INTO business.permission (code, description) VALUES ('expenses.write', 'expenses.write') ON CONFLICT (code) DO NOTHING;
INSERT INTO business.permission (code, description) VALUES ('reports.read', 'reports.read') ON CONFLICT (code) DO NOTHING;

-- Default grants; insert missing grants only.
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'super_admin' AND p.code = 'company.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'super_admin' AND p.code = 'company.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'super_admin' AND p.code = 'users.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'super_admin' AND p.code = 'users.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'super_admin' AND p.code = 'users.assign_roles'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'super_admin' AND p.code = 'roles.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'super_admin' AND p.code = 'roles.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'super_admin' AND p.code = 'fleet.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'super_admin' AND p.code = 'fleet.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'super_admin' AND p.code = 'drivers.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'super_admin' AND p.code = 'drivers.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'super_admin' AND p.code = 'customers.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'super_admin' AND p.code = 'customers.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'super_admin' AND p.code = 'services.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'super_admin' AND p.code = 'services.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'super_admin' AND p.code = 'services.assign'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'super_admin' AND p.code = 'services.close'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'super_admin' AND p.code = 'expenses.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'super_admin' AND p.code = 'expenses.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'super_admin' AND p.code = 'reports.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'company_admin' AND p.code = 'company.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'company_admin' AND p.code = 'company.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'company_admin' AND p.code = 'users.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'company_admin' AND p.code = 'users.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'company_admin' AND p.code = 'users.assign_roles'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'company_admin' AND p.code = 'roles.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'company_admin' AND p.code = 'roles.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'company_admin' AND p.code = 'fleet.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'company_admin' AND p.code = 'fleet.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'company_admin' AND p.code = 'drivers.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'company_admin' AND p.code = 'drivers.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'company_admin' AND p.code = 'customers.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'company_admin' AND p.code = 'customers.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'company_admin' AND p.code = 'services.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'company_admin' AND p.code = 'services.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'company_admin' AND p.code = 'services.assign'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'company_admin' AND p.code = 'services.close'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'company_admin' AND p.code = 'expenses.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'company_admin' AND p.code = 'expenses.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'company_admin' AND p.code = 'reports.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'manager' AND p.code = 'company.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'manager' AND p.code = 'company.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'manager' AND p.code = 'fleet.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'manager' AND p.code = 'fleet.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'manager' AND p.code = 'drivers.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'manager' AND p.code = 'drivers.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'manager' AND p.code = 'customers.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'manager' AND p.code = 'customers.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'manager' AND p.code = 'services.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'manager' AND p.code = 'services.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'manager' AND p.code = 'services.assign'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'manager' AND p.code = 'services.close'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'manager' AND p.code = 'expenses.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'manager' AND p.code = 'expenses.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'manager' AND p.code = 'reports.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'dispatcher' AND p.code = 'fleet.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'dispatcher' AND p.code = 'drivers.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'dispatcher' AND p.code = 'customers.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'dispatcher' AND p.code = 'customers.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'dispatcher' AND p.code = 'services.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'dispatcher' AND p.code = 'services.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'dispatcher' AND p.code = 'services.assign'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'dispatcher' AND p.code = 'reports.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'supervisor' AND p.code = 'fleet.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'supervisor' AND p.code = 'drivers.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'supervisor' AND p.code = 'customers.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'supervisor' AND p.code = 'services.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'supervisor' AND p.code = 'services.close'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'supervisor' AND p.code = 'expenses.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'supervisor' AND p.code = 'expenses.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'supervisor' AND p.code = 'reports.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'driver' AND p.code = 'services.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'driver' AND p.code = 'services.close'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'driver' AND p.code = 'expenses.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'driver' AND p.code = 'expenses.write'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'viewer' AND p.code = 'company.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'viewer' AND p.code = 'users.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'viewer' AND p.code = 'roles.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'viewer' AND p.code = 'fleet.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'viewer' AND p.code = 'drivers.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'viewer' AND p.code = 'customers.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'viewer' AND p.code = 'services.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'viewer' AND p.code = 'expenses.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;
INSERT INTO business.role_permission (role_id, permission_id)
SELECT r.id, p.id FROM business.role r CROSS JOIN business.permission p
WHERE r.tenant_id IS NULL AND r.code = 'viewer' AND p.code = 'reports.read'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- No user, tenant, or tenant_user_role records are created here.
-- Important: authorization must enforce tenant isolation and ownership in the Go API.
-- In particular, driver permissions are not sufficient without an own-service check.
-- Dictionary FK columns in migration 011 are not constrained to a dictionary category;
-- the API must enforce category correctness or a subsequent migration must add DB triggers.
COMMIT;
