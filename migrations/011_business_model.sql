-- Vehitrack Empresarial | Migration 011 | PostgreSQL
-- New business model. Does not alter existing schemas or tables.
-- Monetary values are COP; distances are km unless suffixed _m.
-- Authentication/session/token implementation belongs to the API layer.
BEGIN;
CREATE SCHEMA IF NOT EXISTS business;

-- Shared dictionaries. Values are scoped by dictionary code.
CREATE TABLE business.dictionary (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 code text NOT NULL UNIQUE,
 name text NOT NULL,
 description text,
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT dictionary_code_format CHECK (code ~ '^[a-z][a-z0-9_]*$')
);
CREATE TABLE business.dictionary_value (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 dictionary_id uuid NOT NULL REFERENCES business.dictionary(id),
 code text NOT NULL,
 name text NOT NULL,
 description text,
 sort_order integer NOT NULL DEFAULT 0,
 is_active boolean NOT NULL DEFAULT true,
 UNIQUE (dictionary_id, code),
 CONSTRAINT dictionary_value_code_format CHECK (code ~ '^[a-z][a-z0-9_]*$')
);

-- Tenant extension: one legal/commercial profile, multiple addresses, contacts, documents.
CREATE TABLE business.company_profile (
 tenant_id uuid PRIMARY KEY REFERENCES public.tenant(id),
 legal_name text NOT NULL,
 trade_name text,
 identification_type_id uuid REFERENCES business.dictionary_value(id),
 identification_number text,
 verification_digit text,
 tax_regime_id uuid REFERENCES business.dictionary_value(id),
 industry_code text,
 website text,
 description text,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT company_identification_pair CHECK ((identification_type_id IS NULL) = (identification_number IS NULL))
);
CREATE TABLE business.company_address (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenant(id),
 label text,
 address_line text NOT NULL,
 city text NOT NULL,
 region text,
 country_code varchar(2) NOT NULL DEFAULT 'CO',
 postal_code text,
 latitude numeric(10,7),
 longitude numeric(10,7),
 is_primary boolean NOT NULL DEFAULT false,
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
 CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180)
);
CREATE UNIQUE INDEX company_address_primary_uidx ON business.company_address(tenant_id) WHERE is_primary AND is_active;
CREATE TABLE business.company_contact (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenant(id),
 name text,
 position_title text,
 email text,
 phone text,
 is_primary boolean NOT NULL DEFAULT false,
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 CHECK (email IS NOT NULL OR phone IS NOT NULL)
);
CREATE TABLE business.company_document (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenant(id),
 document_type_id uuid REFERENCES business.dictionary_value(id),
 document_number text,
 file_name text NOT NULL,
 storage_key text NOT NULL,
 mime_type text,
 issued_at date,
 expires_at date,
 uploaded_at timestamptz NOT NULL DEFAULT now(),
 CHECK (expires_at IS NULL OR issued_at IS NULL OR expires_at >= issued_at)
);

-- New enterprise identities; separate from device.account.
CREATE TABLE business."user" (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 email text NOT NULL,
 full_name text NOT NULL,
 password_hash text,
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (email)
);
CREATE UNIQUE INDEX business_user_email_ci_uidx ON business."user"(lower(email));
CREATE TABLE business.tenant_user (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenant(id),
 user_id uuid NOT NULL REFERENCES business."user"(id),
 is_active boolean NOT NULL DEFAULT true,
 joined_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (tenant_id, user_id),
 UNIQUE (id, tenant_id)
);
CREATE TABLE business.role (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid REFERENCES public.tenant(id),
 code text NOT NULL,
 name text NOT NULL,
 description text,
 is_active boolean NOT NULL DEFAULT true,
 UNIQUE (id, tenant_id)
);
CREATE UNIQUE INDEX role_global_code_uidx ON business.role(code) WHERE tenant_id IS NULL;
CREATE UNIQUE INDEX role_tenant_code_uidx ON business.role(tenant_id, code) WHERE tenant_id IS NOT NULL;
CREATE TABLE business.permission (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 code text NOT NULL UNIQUE,
 description text
);
CREATE TABLE business.role_permission (
 role_id uuid NOT NULL REFERENCES business.role(id) ON DELETE CASCADE,
 permission_id uuid NOT NULL REFERENCES business.permission(id) ON DELETE CASCADE,
 PRIMARY KEY (role_id, permission_id)
);
CREATE TABLE business.tenant_user_role (
 tenant_user_id uuid NOT NULL REFERENCES business.tenant_user(id) ON DELETE CASCADE,
 role_id uuid NOT NULL REFERENCES business.role(id),
 assigned_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY (tenant_user_id, role_id)
);
-- API must validate role tenant_id IS NULL OR matches tenant_user.tenant_id.

-- Fleet.
CREATE TABLE business.vehicle (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenant(id),
 plate text NOT NULL,
 vehicle_type_id uuid REFERENCES business.dictionary_value(id),
 brand text,
 model text,
 model_year integer,
 passenger_capacity integer NOT NULL,
 operational_status text NOT NULL DEFAULT 'available',
 cost_per_km_cop numeric(14,2) NOT NULL DEFAULT 0,
 fuel_efficiency_km_per_gallon numeric(12,3),
 dispatch_cost_cop numeric(14,2) NOT NULL DEFAULT 0,
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (tenant_id, plate),
 UNIQUE (id, tenant_id),
 CHECK (passenger_capacity > 0),
 CHECK (model_year IS NULL OR model_year BETWEEN 1900 AND 2200),
 CHECK (cost_per_km_cop >= 0 AND dispatch_cost_cop >= 0),
 CHECK (fuel_efficiency_km_per_gallon IS NULL OR fuel_efficiency_km_per_gallon > 0),
 CHECK (operational_status IN ('available','assigned','maintenance','inactive'))
);
CREATE TABLE business.vehicle_device (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenant(id),
 vehicle_id uuid NOT NULL,
 device_id uuid NOT NULL,
 assigned_at timestamptz NOT NULL DEFAULT now(),
 unassigned_at timestamptz,
 FOREIGN KEY (vehicle_id, tenant_id) REFERENCES business.vehicle(id, tenant_id),
 FOREIGN KEY (device_id) REFERENCES device.device(id),
 CHECK (unassigned_at IS NULL OR unassigned_at > assigned_at)
);
CREATE UNIQUE INDEX vehicle_device_active_vehicle_uidx ON business.vehicle_device(vehicle_id) WHERE unassigned_at IS NULL;
CREATE UNIQUE INDEX vehicle_device_active_device_uidx ON business.vehicle_device(device_id) WHERE unassigned_at IS NULL;
CREATE TABLE business.vehicle_document (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenant(id),
 vehicle_id uuid NOT NULL,
 document_type_id uuid REFERENCES business.dictionary_value(id),
 document_number text,
 file_name text NOT NULL,
 storage_key text NOT NULL,
 issued_at date,
 expires_at date,
 uploaded_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (vehicle_id, tenant_id) REFERENCES business.vehicle(id, tenant_id),
 CHECK (expires_at IS NULL OR issued_at IS NULL OR expires_at >= issued_at)
);
CREATE TABLE business.vehicle_maintenance (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenant(id),
 vehicle_id uuid NOT NULL,
 performed_at date NOT NULL,
 description text NOT NULL,
 odometer_km numeric(14,2),
 amount_cop numeric(14,2) NOT NULL DEFAULT 0,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (vehicle_id, tenant_id) REFERENCES business.vehicle(id, tenant_id),
 CHECK (odometer_km IS NULL OR odometer_km >= 0),
 CHECK (amount_cop >= 0)
);
CREATE TABLE business.vehicle_expense (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenant(id),
 vehicle_id uuid NOT NULL,
 expense_type_id uuid REFERENCES business.dictionary_value(id),
 description text,
 amount_cop numeric(14,2) NOT NULL,
 incurred_at date NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (vehicle_id, tenant_id) REFERENCES business.vehicle(id, tenant_id),
 CHECK (amount_cop >= 0)
);

-- Drivers and their historical assignments.
CREATE TABLE business.driver (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenant(id),
 tenant_user_id uuid,
 full_name text NOT NULL,
 identification_number text,
 phone text,
 license_number text,
 license_category text,
 license_expires_at date,
 operational_status text NOT NULL DEFAULT 'available',
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (id, tenant_id),
 FOREIGN KEY (tenant_user_id, tenant_id) REFERENCES business.tenant_user(id, tenant_id),
 CHECK (operational_status IN ('available','assigned','rest','inactive'))
);
CREATE UNIQUE INDEX driver_tenant_user_uidx ON business.driver(tenant_user_id) WHERE tenant_user_id IS NOT NULL;
CREATE TABLE business.driver_document (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenant(id),
 driver_id uuid NOT NULL,
 document_type_id uuid REFERENCES business.dictionary_value(id),
 document_number text,
 file_name text NOT NULL,
 storage_key text NOT NULL,
 issued_at date,
 expires_at date,
 uploaded_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (driver_id, tenant_id) REFERENCES business.driver(id, tenant_id),
 CHECK (expires_at IS NULL OR issued_at IS NULL OR expires_at >= issued_at)
);
CREATE TABLE business.driver_vehicle (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenant(id),
 driver_id uuid NOT NULL,
 vehicle_id uuid NOT NULL,
 assigned_at timestamptz NOT NULL,
 unassigned_at timestamptz,
 FOREIGN KEY (driver_id, tenant_id) REFERENCES business.driver(id, tenant_id),
 FOREIGN KEY (vehicle_id, tenant_id) REFERENCES business.vehicle(id, tenant_id),
 CHECK (unassigned_at IS NULL OR unassigned_at > assigned_at)
);
CREATE INDEX driver_vehicle_driver_idx ON business.driver_vehicle(driver_id, assigned_at DESC);
CREATE INDEX driver_vehicle_vehicle_idx ON business.driver_vehicle(vehicle_id, assigned_at DESC);
CREATE TABLE business.driver_availability (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenant(id),
 driver_id uuid NOT NULL,
 starts_at timestamptz NOT NULL,
 ends_at timestamptz NOT NULL,
 availability_status text NOT NULL DEFAULT 'available',
 FOREIGN KEY (driver_id, tenant_id) REFERENCES business.driver(id, tenant_id),
 CHECK (ends_at > starts_at),
 CHECK (availability_status IN ('available','unavailable','rest'))
);

-- Customers and services.
CREATE TABLE business.customer (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenant(id),
 name text NOT NULL,
 identification_number text,
 email text,
 phone text,
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (id, tenant_id)
);
CREATE TABLE business.customer_contact (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenant(id),
 customer_id uuid NOT NULL,
 name text NOT NULL,
 email text,
 phone text,
 position_title text,
 FOREIGN KEY (customer_id, tenant_id) REFERENCES business.customer(id, tenant_id),
 CHECK (email IS NOT NULL OR phone IS NOT NULL)
);
CREATE TABLE business.service_request (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenant(id),
 customer_id uuid,
 origin_address text NOT NULL,
 origin_latitude numeric(10,7),
 origin_longitude numeric(10,7),
 destination_address text NOT NULL,
 destination_latitude numeric(10,7),
 destination_longitude numeric(10,7),
 scheduled_at timestamptz NOT NULL,
 passenger_count integer NOT NULL,
 agreed_fare_cop numeric(14,2) NOT NULL DEFAULT 0,
 status text NOT NULL DEFAULT 'pending',
 notes text,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (id, tenant_id),
 FOREIGN KEY (customer_id, tenant_id) REFERENCES business.customer(id, tenant_id),
 CHECK (passenger_count > 0 AND agreed_fare_cop >= 0),
 CHECK (status IN ('pending','assigned','completed','cancelled')),
 CHECK (origin_latitude IS NULL OR origin_latitude BETWEEN -90 AND 90),
 CHECK (origin_longitude IS NULL OR origin_longitude BETWEEN -180 AND 180),
 CHECK (destination_latitude IS NULL OR destination_latitude BETWEEN -90 AND 90),
 CHECK (destination_longitude IS NULL OR destination_longitude BETWEEN -180 AND 180)
);
CREATE TABLE business.service_assignment (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenant(id),
 service_request_id uuid NOT NULL,
 vehicle_id uuid NOT NULL,
 driver_id uuid NOT NULL,
 route_cache_id bigint REFERENCES routing.route_cache(id),
 estimated_empty_km numeric(12,3),
 estimated_service_km numeric(12,3),
 estimated_cost_cop numeric(14,2),
 estimated_margin_cop numeric(14,2),
 criteria_explanation text,
 cost_breakdown jsonb,
 status text NOT NULL DEFAULT 'proposed',
 assigned_at timestamptz NOT NULL DEFAULT now(),
 confirmed_at timestamptz,
 cancelled_at timestamptz,
 UNIQUE (id, tenant_id),
 FOREIGN KEY (service_request_id, tenant_id) REFERENCES business.service_request(id, tenant_id),
 FOREIGN KEY (vehicle_id, tenant_id) REFERENCES business.vehicle(id, tenant_id),
 FOREIGN KEY (driver_id, tenant_id) REFERENCES business.driver(id, tenant_id),
 CHECK (status IN ('proposed','confirmed','cancelled')),
 CHECK (estimated_empty_km IS NULL OR estimated_empty_km >= 0),
 CHECK (estimated_service_km IS NULL OR estimated_service_km >= 0),
 CHECK (estimated_cost_cop IS NULL OR estimated_cost_cop >= 0)
);
CREATE UNIQUE INDEX service_assignment_confirmed_uidx ON business.service_assignment(service_request_id) WHERE status = 'confirmed';
CREATE TABLE business.service_execution (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenant(id),
 service_assignment_id uuid NOT NULL,
 started_at timestamptz,
 ended_at timestamptz,
 actual_distance_km numeric(14,3),
 registered_income_cop numeric(14,2),
 status text NOT NULL DEFAULT 'in_progress',
 notes text,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (service_assignment_id),
 UNIQUE (id, tenant_id),
 FOREIGN KEY (service_assignment_id, tenant_id) REFERENCES business.service_assignment(id, tenant_id),
 CHECK (ended_at IS NULL OR started_at IS NULL OR ended_at >= started_at),
 CHECK (actual_distance_km IS NULL OR actual_distance_km >= 0),
 CHECK (registered_income_cop IS NULL OR registered_income_cop >= 0),
 CHECK (status IN ('in_progress','completed','cancelled'))
);
CREATE TABLE business.service_stop (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenant(id),
 service_execution_id uuid NOT NULL,
 stop_order integer NOT NULL,
 stop_type text NOT NULL,
 address text NOT NULL,
 latitude numeric(10,7),
 longitude numeric(10,7),
 arrived_at timestamptz,
 FOREIGN KEY (service_execution_id, tenant_id) REFERENCES business.service_execution(id, tenant_id),
 UNIQUE (service_execution_id, stop_order),
 CHECK (stop_order >= 0),
 CHECK (stop_type IN ('origin','stop','destination')),
 CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
 CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180)
);
-- One enterprise execution may include multiple GPS trips; GPS is optional.
CREATE TABLE business.service_trip (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenant(id),
 service_execution_id uuid NOT NULL,
 trip_id uuid REFERENCES tracking.trip(id),
 distance_km numeric(14,3),
 recorded_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (id, tenant_id),
 UNIQUE (trip_id),
 FOREIGN KEY (service_execution_id, tenant_id) REFERENCES business.service_execution(id, tenant_id),
 CHECK (distance_km IS NULL OR distance_km >= 0)
);
CREATE TABLE business.trip_expense (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenant(id),
 service_trip_id uuid NOT NULL,
 expense_type text NOT NULL,
 amount_cop numeric(14,2) NOT NULL,
 description text,
 incurred_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (service_trip_id, tenant_id) REFERENCES business.service_trip(id, tenant_id),
 CHECK (amount_cop >= 0),
 CHECK (expense_type IN ('fuel','toll','maintenance','driver','other'))
);
CREATE TABLE business.trip_income (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenant(id),
 service_trip_id uuid NOT NULL,
 amount_cop numeric(14,2) NOT NULL,
 description text,
 received_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (service_trip_id, tenant_id) REFERENCES business.service_trip(id, tenant_id),
 CHECK (amount_cop >= 0)
);

CREATE INDEX tenant_user_tenant_idx ON business.tenant_user(tenant_id);
CREATE INDEX vehicle_tenant_status_idx ON business.vehicle(tenant_id, operational_status);
CREATE INDEX driver_tenant_status_idx ON business.driver(tenant_id, operational_status);
CREATE INDEX service_request_tenant_date_idx ON business.service_request(tenant_id, scheduled_at DESC);
CREATE INDEX service_assignment_request_idx ON business.service_assignment(service_request_id);
CREATE INDEX service_execution_tenant_status_idx ON business.service_execution(tenant_id, status);
CREATE INDEX service_trip_execution_idx ON business.service_trip(service_execution_id);
CREATE INDEX trip_expense_trip_idx ON business.trip_expense(service_trip_id);
CREATE INDEX trip_income_trip_idx ON business.trip_income(service_trip_id);

-- Financial aggregation: real income and costs per enterprise execution.
-- Avoid adding tracking.trip.cost_cop to detailed expenses automatically.
CREATE VIEW business.service_profitability AS
SELECT e.id AS service_execution_id, e.tenant_id, a.service_request_id,
       a.estimated_cost_cop, a.estimated_margin_cop,
       COALESCE(inc.total_income_cop, e.registered_income_cop, 0) AS actual_income_cop,
       COALESCE(exp.total_expense_cop, 0) AS actual_expense_cop,
       COALESCE(inc.total_income_cop, e.registered_income_cop, 0) - COALESCE(exp.total_expense_cop, 0) AS actual_margin_cop
FROM business.service_execution e
JOIN business.service_assignment a ON a.id = e.service_assignment_id
LEFT JOIN (
 SELECT st.service_execution_id, SUM(i.amount_cop) AS total_income_cop
 FROM business.service_trip st JOIN business.trip_income i ON i.service_trip_id = st.id
 GROUP BY st.service_execution_id
) inc ON inc.service_execution_id = e.id
LEFT JOIN (
 SELECT st.service_execution_id, SUM(x.amount_cop) AS total_expense_cop
 FROM business.service_trip st JOIN business.trip_expense x ON x.service_trip_id = st.id
 GROUP BY st.service_execution_id
) exp ON exp.service_execution_id = e.id;

COMMENT ON SCHEMA business IS 'Enterprise management model; tenant is owned by public.tenant.';
COMMENT ON TABLE business."user" IS 'Independent enterprise identity; not device.account. API manages authentication and password hashes.';
COMMENT ON TABLE business.vehicle_device IS 'Links enterprise vehicles to technical devices; application must verify matching device.tenant_id.';
COMMENT ON TABLE business.service_trip IS 'Optional link between an enterprise service and tracking.trip; API must verify matching trip.tenant_id.';
COMMENT ON TABLE business.tenant_user_role IS 'API must ensure role is global or belongs to the same tenant as tenant_user.';
COMMENT ON VIEW business.service_profitability IS 'Actual margin from detailed enterprise expenses and incomes; does not automatically add tracking.trip.cost_cop.';
COMMIT;
