# UBER MAIDS WATCH MANAGEMENT SYSTEM
## Software Development Blueprint and Implementation Roadmap

**Project code:** UMWMS  
**Document version:** 1.0  
**Prepared for:** UBER MAIDS WATCH  
**Prepared by:** Michael – Software Developer  
**Purpose:** Product planning, system design, implementation guidance, and handoff instructions for Codex or OpenCode.

---

## 1. Project vision

Build a secure, reliable business platform that helps UBER MAIDS WATCH manage its domestic-worker recruitment, verification, training, client requests, placements, daily follow-ups, replacement guarantees, and business administration.

The system must digitize the business processes that support the company's promises:

- Domestic workers are vetted and their identity and family contacts are documented.
- Workers have identification and local-reference details recorded.
- Workers receive customer-service and conduct training.
- Placements are tracked after a worker is assigned to a client.
- Replacement requests are recorded and handled within the applicable guarantee period.
- The business can coordinate backup workers and follow up with clients.

The software must support these real processes. It must not simply be a generic booking website.

### 1.1 Primary objectives

1. Keep one reliable record for every worker, client, booking, placement, and follow-up.
2. Reduce manual searching, duplicate records, and missed follow-ups.
3. Make worker vetting and document status visible to authorized staff.
4. Track the two-week free replacement guarantee (confirm the exact policy with the owner before configuration).
5. Support daily tracking and same-day backup workflows.
6. Give clients a clear way to discover services and submit requests online.
7. Provide management with reports for bookings, placements, revenue, replacements, and worker availability.
8. Protect personal information and sensitive identity documents.

### 1.2 What success looks like

- Staff can find a worker or client record quickly.
- Staff can see whether a worker's verification file is complete.
- Every placement has a start date, status, assigned worker, client, and follow-up history.
- Guarantee expiry and follow-up dates are calculated and displayed.
- Replacement cases can be opened, assigned, resolved, and audited.
- Public users can submit a service request without accessing private worker records.
- Management can see operational performance from a dashboard.

---

## 2. Product scope and architecture

### 2.1 Important architecture decision

Java Swing is suitable for the internal desktop management application. It is not a website technology. Therefore, build the system as a central backend with separate user interfaces:

1. **Java Swing desktop application:** used by office staff and managers.
2. **Public website:** used by customers to learn about services and submit enquiries or booking requests.
3. **Java Spring Boot backend:** shared business rules, authentication, API, and workflows.
4. **PostgreSQL database:** central source of truth for all system records.

All interfaces communicate with the same backend. Do not connect the Swing application directly to the production database.

### 2.2 Recommended technology stack

| Layer | Technology | Purpose |
|---|---|---|
| Desktop UI | Java Swing | Internal staff application |
| Backend | Java + Spring Boot | Business logic and REST API |
| API style | REST + JSON | Communication between clients and backend |
| Database | PostgreSQL | Persistent business data |
| ORM | Spring Data JPA / Hibernate | Database persistence |
| Migrations | Flyway | Version-controlled database changes |
| Security | Spring Security | Authentication and authorization |
| Validation | Jakarta Bean Validation | Input validation |
| Build | Maven | Dependency and build management |
| Testing | JUnit 5, Mockito, Spring Boot Test | Unit and integration tests |
| API documentation | springdoc-openapi / OpenAPI | API reference |
| Desktop packaging | jpackage | Windows installer/package |
| Deployment | Docker Compose initially | Repeatable server deployment |
| Version control | Git + GitHub | Source control and collaboration |

Use a currently supported Java LTS release and compatible Spring Boot release. The coding agent must verify compatibility before creating the project and must document the chosen versions in the README.

### 2.3 High-level architecture

```text
CUSTOMER BROWSER
      |
      v
PUBLIC WEBSITE
      |
      | HTTPS / REST API
      v
JAVA SPRING BOOT BACKEND
  - Authentication and permissions
  - Worker management
  - Client management
  - Booking and placement workflows
  - Tracking and follow-ups
  - Replacement management
  - Reports and notifications
      |
      +--------------------+
      |                    |
      v                    v
POSTGRESQL           PRIVATE FILE STORAGE
      ^              (ID documents, photos,
      |               verification files)
      |
JAVA SWING DESKTOP APPLICATION
  - Dashboard
  - Worker records
  - Client records
  - Bookings and placements
  - Follow-ups and replacements
  - Reports and settings
```

**Security rule:** Private documents must be stored outside public web folders. The database stores secure file references and metadata, not publicly accessible file URLs. Access to a file must be authorized by the backend.

---

## 3. Users, roles, and permissions

Implement role-based access control. Start with these roles; the owner may rename or adjust them after discovery.

| Role | Main permissions |
|---|---|
| Owner / Administrator | Full access, user management, settings, reports, audit logs |
| Operations Manager | Workers, clients, bookings, placements, tracking, replacements |
| Recruitment / Verification Officer | Worker registration, documents, references, verification status |
| Customer Care Officer | Client enquiries, bookings, feedback, follow-ups |
| Finance Officer | Payments, receipts, financial reports |
| Read-only Manager | View permitted dashboards and reports without editing |

Permissions must be enforced in the backend, not only by hiding buttons in Swing.

Every staff account must have an individual login. Do not create shared staff accounts.

---

## 4. Functional modules

### Module 1: Authentication and user administration

Features:
- Login and logout.
- Secure password hashing.
- Role and permission assignment.
- Activate/deactivate staff accounts.
- Password reset process.
- Record last login and relevant security events.
- Session timeout and safe logout.

Acceptance criteria:
- An unauthenticated user cannot access protected endpoints.
- A user cannot perform an action outside their role.
- Passwords are never stored in plain text.
- Disabling a staff account prevents future authentication.

### Module 2: Dashboard

Show useful operational indicators:
- New enquiries awaiting response.
- Bookings awaiting confirmation.
- Workers available for placement.
- Workers awaiting verification.
- Active placements.
- Follow-ups due today.
- Replacement cases open.
- Guarantee periods nearing expiry.
- Recent activity.

Dashboard values must come from backend queries, not hard-coded sample numbers.

### Module 3: Domestic worker management

Each worker profile should include:

**Basic details**
- Internal worker number (generated).
- Full name.
- Photograph.
- Phone number.
- General residential area.
- Date of birth or age only if operationally necessary and lawfully collected.
- Emergency contact.

**Identity and verification**
- National ID type and number, where applicable.
- ID document file reference.
- LC1 letter/reference status and details, where applicable.
- Family / next-of-kin contact details.
- Reference checks and verification notes.
- Verification officer, date, and status.

**Professional details**
- Skills and service categories.
- Previous experience.
- Languages.
- Training completed.
- Availability.
- Expected salary or placement terms, if applicable.
- Internal notes.

**Status values**
- Applicant
- Documents Pending
- Under Verification
- Verified
- Training
- Available
- Reserved
- Placed
- On Leave
- Suspended
- Inactive

Rules:
- Do not allow a worker to be marked Verified unless required verification checks are complete or an authorized manager records an explicit exception with a reason.
- Keep a history of status changes.
- Do not display private ID numbers, family contacts, or verification files on public worker profiles.
- Restrict sensitive fields to authorized roles.

### Module 4: Client management

Client fields:
- Client number.
- Full name.
- Phone number.
- Email (optional).
- General location / service area.
- Preferred contact method.
- Date registered.
- Notes and communication preferences.

Client history:
- Enquiries.
- Booking requests.
- Placements.
- Payments.
- Complaints and feedback.
- Replacement cases.
- Follow-up records.

Avoid collecting unnecessary personal information. Record only what the business needs.

### Module 5: Services and packages

Allow administrators to configure:
- Maid / house helper.
- Babysitter / childcare.
- Cleaner.
- Cook.
- Laundry / ironing.
- Other owner-approved services.

Each service/package should have:
- Name and description.
- Price or price range.
- Placement type / duration.
- Requirements.
- Active/inactive status.
- Public visibility setting.

Do not hard-code prices or policies. Confirm all pricing, deposits, refunds, and package rules with Evelyn before launch.

### Module 6: Enquiries and booking requests

Booking workflow:

```text
New Enquiry
   |
   v
Requirements Captured
   |
   v
Availability Checked
   |
   v
Quote / Package Shared
   |
   v
Client Confirms
   |
   v
Booking Confirmed
   |
   v
Worker Selected
   |
   v
Placement Created
```

Booking fields:
- Booking reference.
- Client.
- Requested service.
- Preferred start date.
- Work location / service area.
- Schedule or duration.
- Skills and experience requested.
- Budget / price agreed (if applicable).
- Special instructions.
- Assigned staff member.
- Booking status and timestamps.

Statuses:
- New
- Contacted
- Requirements Confirmed
- Awaiting Client
- Awaiting Worker
- Confirmed
- Cancelled
- Converted to Placement
- Closed

The public website must create a booking request, not automatically expose worker private data or promise a confirmed worker before staff review.

### Module 7: Placement management

A placement links one client, one worker, and one confirmed booking.

Placement fields:
- Placement reference.
- Booking reference.
- Client.
- Worker.
- Placement start date.
- Agreed terms.
- Placement status.
- Guarantee duration and calculated end date.
- Staff member responsible.
- Client acknowledgement / confirmation record.
- Placement notes.

Statuses:
- Preparing
- Active
- Paused
- Completed
- Terminated
- Replacement Requested

The guarantee duration must be configurable. The current business message says two weeks of free replacement; confirm whether this means 14 calendar days, what conditions apply, and when the period begins. Do not assume these details.

### Module 8: Daily tracking and follow-ups

This module supports the company's daily tracking promise.

Features:
- Follow-up schedule for each active placement.
- Record date, time, staff member, contact method, and outcome.
- Record client satisfaction.
- Record worker attendance / status only through an agreed and lawful process.
- Create an issue when a client reports a problem.
- Assign an issue to a staff member.
- Set next follow-up date.
- Escalate overdue follow-ups on the dashboard.

Possible follow-up outcomes:
- Client satisfied
- Worker settled in
- Client requested support
- Worker unavailable
- Conduct concern
- Replacement requested
- Client unreachable
- Other (with notes)

Do not introduce GPS or continuous location tracking in the first release. If the business later requests location features, assess consent, worker safety, legal requirements, and data minimization separately.

### Module 9: Replacement and backup management

This is a key differentiator and should be designed carefully.

Replacement workflow:

```text
Client Reports Problem
        |
        v
Replacement Case Opened
        |
        v
Original Placement and Guarantee Checked
        |
        v
Manager Reviews Eligibility
        |
        +---- Not Eligible --> Reason Recorded / Client Informed
        |
        v
Eligible Replacement Approved
        |
        v
Available Backup Worker Identified
        |
        v
Replacement Worker Assigned
        |
        v
Client Confirms
        |
        v
Case Resolved and Audited
```

Replacement case fields:
- Case reference.
- Original placement.
- Client.
- Original worker.
- Date issue reported.
- Problem category.
- Description and supporting notes.
- Guarantee eligibility result.
- Eligibility decision and reason.
- Approved by.
- Replacement worker.
- Replacement date.
- Resolution status.
- Client confirmation.

Problem categories may include:
- Worker left / absconded.
- Conduct complaint.
- Skills mismatch.
- Theft allegation.
- Attendance / reliability.
- Other.

Treat allegations as allegations. Record factual reports and investigation outcomes without automatically labeling a worker guilty.

Backup worker management:
- Search workers by service skills, availability, area, and verification status.
- Reserve a candidate.
- Record client approval.
- Convert approved assignment into a replacement placement.
- Maintain the original placement and case history.

### Module 10: Payments and finance records

For the first release:
- Record charges and agreed fees.
- Record payment date, amount, currency, payment method, and reference.
- Support cash and mobile money as recorded payment methods.
- Generate a receipt reference.
- Track unpaid / partially paid / paid / refunded status.
- Provide daily and monthly summaries.

Do not integrate directly with a mobile money provider until the owner confirms providers, merchant accounts, settlement process, fees, and reconciliation requirements. Initial release can record payments manually.

### Module 11: Reports

Initial reports:
- Worker register and status.
- Verification completion.
- Available workers by skill.
- New enquiries by date.
- Bookings by status.
- Placements by period.
- Active placements.
- Follow-ups due and overdue.
- Replacement cases and reasons.
- Guarantee cases and outcomes.
- Payments collected and outstanding balances.
- Staff activity.

Allow date filters and CSV export. Restrict reports containing sensitive information.

### Module 12: Public website

Public pages:
1. Home
2. About UBER MAIDS WATCH
3. Services
4. How It Works
5. Our Vetting and Training Process
6. Frequently Asked Questions
7. Testimonials (only genuine, approved testimonials)
8. Contact
9. Request a Service / Book a Consultation
10. Privacy Notice and Terms

Design goals:
- Mobile-first and fast.
- Clear call-to-action: Book a Maid / Request a Service.
- Prominent phone and WhatsApp contact.
- Explain vetting, training, tracking, and replacement policies accurately.
- Search-engine-friendly page titles, descriptions, and structured content.
- No private worker identity documents or family contacts.
- Public worker profiles should be optional and require explicit approval and consent.

The website should submit requests to the same Spring Boot backend and show a reference number. It should not claim a booking is confirmed until staff confirms it.

---

## 5. Desktop application UI / visual direction

### 5.1 Overall look

Build a polished, modern Windows desktop application. It should feel like a professional business management product, not a basic Java classroom project.

Suggested visual direction:
- Primary color: deep violet / purple.
- Accent: warm coral or muted gold, used sparingly.
- Background: very light grey.
- Cards: white with subtle borders.
- Text: dark charcoal.
- Typography: clean sans-serif such as Segoe UI.
- Icons: consistent line icons.
- Spacing: generous and consistent.
- Tables: readable, alternating row backgrounds, clear status labels.
- Buttons: consistent height, clear primary and secondary actions.

Suggested palette (confirm with owner):
- Primary: `#6C2BD9`
- Primary dark: `#4E1FA8`
- Accent: `#E8A23A`
- Background: `#F5F6FA`
- Surface: `#FFFFFF`
- Text: `#202333`
- Muted text: `#73788C`
- Success: `#21865B`
- Warning: `#D58B18`
- Danger: `#C74646`

### 5.2 Main application layout

```text
+--------------------------------------------------------------------------------+
| UBER MAIDS WATCH       Search records...            Notifications   User Menu |
+----------------------+---------------------------------------------------------+
| LOGO                 | Dashboard                                               |
|                      |                                                         |
| Dashboard            | +-------------+ +-------------+ +--------------------+ |
| Workers              | | New Requests| | Active      | | Follow-ups Due     | |
| Clients              | |      12     | | Placements  | |         5          | |
| Bookings             | |             | |      28     | |                    | |
| Placements           | +-------------+ +-------------+ +--------------------+ |
| Tracking             |                                                         |
| Replacements         | +--------------------------------+ +----------------+ |
| Payments             | | Recent Bookings                | | Quick Actions  | |
| Reports              | | Ref  Client  Service  Status    | | + Add Worker   | |
| Staff & Roles         | | ...                            | | + New Booking  | |
| Settings              | +--------------------------------+ | + Add Client   | |
|                      |                                      +----------------+ |
|                      | Recent Activity                                         |
+----------------------+---------------------------------------------------------+
```

### 5.3 Required screens

Build these screens with consistent layouts:

- Login screen.
- Main dashboard.
- Worker list and worker profile.
- Add/edit worker form.
- Verification checklist and document viewer.
- Client list and client profile.
- Service/package management.
- Booking list and booking details.
- Create booking form.
- Placement list and placement details.
- Follow-up calendar/list.
- Replacement cases list and case details.
- Payment register and receipt view.
- Reports.
- Staff users and roles.
- Audit log.
- System settings.

### 5.4 Interaction standards

- Use a left navigation sidebar and a top bar.
- Main content should use a consistent page title, short description, and action buttons.
- Use tables with search, filters, sorting, and pagination.
- Use modal dialogs for small confirmations only; use full forms for complex records.
- Show loading, empty, success, and error states.
- Validate fields before submission and show understandable messages.
- Confirm destructive actions.
- Do not use blocking network calls on the Swing Event Dispatch Thread. Use `SwingWorker` or an equivalent background execution approach.
- Keep API communication in service/client classes, not inside button event handlers.
- Use a central design system for colors, fonts, spacing, buttons, tables, and form components.

---

## 6. Initial database design

Use PostgreSQL. Use UUID primary keys or another consistent generated identifier strategy. Include `created_at`, `updated_at`, and appropriate user/audit references on important records.

### 6.1 Main tables

| Table | Purpose |
|---|---|
| users | Staff login accounts |
| roles | Roles such as Admin and Operations |
| permissions | Fine-grained permissions |
| user_roles | User-role assignments |
| workers | Domestic worker profiles |
| worker_documents | Private document metadata and secure storage keys |
| worker_references | Family and other reference contacts |
| worker_skills | Skills assigned to workers |
| skills | Controlled list of skills |
| training_records | Training completed by workers |
| verification_checks | Verification checklist and results |
| clients | Customer records |
| services | Service catalogue |
| service_packages | Configurable packages and prices |
| enquiries | Initial customer enquiries |
| bookings | Customer service requests |
| placements | Worker-client assignments |
| follow_ups | Scheduled and completed follow-ups |
| incidents | Issues reported during placements |
| replacement_cases | Replacement requests and decisions |
| payments | Payment records |
| notifications | In-app notification records |
| audit_logs | Sensitive and important action history |
| app_settings | Configurable business rules |

### 6.2 Key relationships

- One client can have many enquiries, bookings, placements, and payments.
- One worker can have many documents, references, skills, training records, verification checks, and placements over time.
- One booking belongs to one client and one requested service; it may later result in a placement.
- One placement links one client and one worker.
- One placement can have many follow-ups and incidents.
- One replacement case belongs to an original placement and may link to a replacement placement.
- One payment belongs to a client and may reference a booking or placement.
- Every important action should record the staff user responsible.

### 6.3 Database design rules

- Use foreign keys and indexes.
- Add unique constraints for worker numbers, client numbers, booking references, and placement references.
- Use database transactions for workflows that create or update multiple related records.
- Use soft deletion or archival for business records where appropriate; do not casually delete financial, placement, or audit history.
- Store dates and timestamps consistently. Configure and display the business timezone as `Africa/Kampala`.
- Store money as decimal values, never floating-point values.
- Store currency explicitly, defaulting to UGX only after confirmation.
- Store document metadata in the database and files in private storage.
- Use migrations for every schema change.

---

## 7. Security, privacy, and reliability

Security must be part of the first implementation, not a final polishing task.

### Required controls

1. Passwords hashed with a modern adaptive password hashing algorithm through Spring Security.
2. Backend authorization for every protected operation.
3. HTTPS for all production traffic.
4. Private document storage with authorized download endpoints.
5. File upload restrictions: allowed formats, size limits, content checks, and safe filenames.
6. Input validation on both desktop and backend.
7. Protection against SQL injection through parameterized ORM/repository access.
8. Audit logs for document access, verification changes, placement changes, replacement decisions, payment edits, and user administration.
9. Backups with a documented restore test.
10. Environment variables or secret management for credentials; never commit secrets.
11. Rate limiting and abuse protection for public booking forms and login endpoints.
12. Least-privilege database and server accounts.
13. Data retention and deletion procedures approved by the business.
14. Privacy notice and informed consent for worker and client information.

The owner should confirm applicable Ugandan privacy and data-protection obligations before production launch. Collect only necessary information and define who can access it.

### Reliability

- Validate all data at the backend boundary.
- Use database transactions for multi-step operations.
- Provide clear error messages without exposing stack traces or secrets.
- Log errors with correlation/request IDs.
- Add health checks for the backend and database.
- Test database backup restoration.
- Ensure the desktop app handles server downtime gracefully and does not silently lose user changes.

---

## 8. Development phases and deliverables

Work in small phases. Each phase must compile, run, and be tested before the next phase begins.

### Phase 0 — Discovery and confirmation

Tasks:
- Interview Evelyn and document current workflows.
- Confirm service categories and package/pricing rules.
- Confirm exact two-week guarantee conditions and start/end calculation.
- Confirm what daily tracking means operationally.
- Confirm same-day backup process and who approves replacements.
- Confirm staff roles and who can see sensitive documents.
- Confirm whether the public website should show individual worker profiles.
- Confirm hosting, domain, brand assets, and contact channels.

Deliverables:
- Signed-off requirements list.
- Workflow diagrams.
- Business rules register.
- Open questions list.

**Do not guess unresolved policies.** Make them configurable or mark them as pending owner approval.

### Phase 1 — Project foundation

Tasks:
- Create Git repository and project README.
- Create Maven Spring Boot backend.
- Create PostgreSQL development environment with Docker Compose.
- Configure Flyway.
- Add health endpoint and OpenAPI documentation.
- Create Java Swing Maven desktop project.
- Add shared configuration and API client structure.
- Establish code formatting, package naming, and test conventions.

Deliverables:
- Backend starts locally.
- Database starts locally.
- Desktop application opens.
- Desktop can call a test backend endpoint.
- CI build and tests run.

### Phase 2 — Authentication and access control

Tasks:
- Implement staff user and role tables.
- Implement login and secure password handling.
- Implement authorization checks.
- Build Swing login screen.
- Build staff and role management screens.
- Add audit events for authentication and user changes.

Deliverables:
- Role-protected API.
- Working desktop login.
- Tests proving access restrictions.

### Phase 3 — Worker management

Tasks:
- Build worker database model and migrations.
- Implement worker CRUD API.
- Implement secure document metadata and private file upload/download.
- Implement worker status history.
- Build worker list, search, filters, profile, and forms in Swing.
- Implement verification checklist and role restrictions.

Deliverables:
- Staff can register, search, edit, and archive workers.
- Authorized staff can upload and view private documents.
- Verification status is controlled and auditable.

### Phase 4 — Clients, services, and bookings

Tasks:
- Implement clients and client history.
- Implement service catalogue and packages.
- Implement enquiry and booking workflows.
- Build client, service, and booking Swing screens.
- Add booking reference generation and status history.

Deliverables:
- Staff can register clients, configure services, and manage booking requests.

### Phase 5 — Placements, tracking, and replacements

Tasks:
- Implement placement creation and lifecycle.
- Implement configurable guarantee rules.
- Implement follow-up scheduling and completion records.
- Implement incident management.
- Implement replacement eligibility review and approval workflow.
- Implement backup worker search and replacement assignment.
- Build all corresponding Swing screens.

Deliverables:
- Full placement-to-follow-up-to-replacement workflow.
- Guarantee dates and overdue follow-ups visible.
- Audit history available.

### Phase 6 — Payments and reports

Tasks:
- Implement manual payment records.
- Generate receipt references.
- Implement financial and operational reports.
- Add filters and CSV exports.
- Restrict sensitive reports by role.

Deliverables:
- Payment register, receipts, and core management reports.

### Phase 7 — Public website

Tasks:
- Implement responsive public pages.
- Add enquiry and booking request forms.
- Connect forms to backend API.
- Add spam protection and validation.
- Add privacy and terms pages.
- Add search metadata and analytics only with appropriate privacy controls.
- Test mobile layouts and accessibility.

Deliverables:
- Public website deployed to staging.
- Enquiries appear in the internal desktop application.

### Phase 8 — Quality assurance and launch

Tasks:
- Unit, integration, API, UI, and user acceptance testing.
- Test permissions and sensitive document access.
- Test guarantee calculations and replacement workflows.
- Test backup restoration.
- Test slow network and backend downtime.
- Fix defects and document known limitations.
- Train staff.
- Deploy production system and monitor.

Deliverables:
- User acceptance sign-off.
- Deployment and rollback instructions.
- Backup and restore instructions.
- User guide and administrator guide.
- Production release.

---

## 9. Testing strategy and acceptance checklist

### Core workflow tests

- Register a worker.
- Upload an identity document securely.
- Complete verification checks.
- Prevent unauthorized staff from viewing restricted records.
- Register a client.
- Create a booking request.
- Confirm a booking.
- Assign a verified available worker.
- Create a placement.
- Calculate guarantee end date using the approved business rule.
- Schedule and complete follow-ups.
- Open a replacement case.
- Approve or reject eligibility with a recorded reason.
- Assign a backup worker.
- Record payment and generate receipt reference.
- Confirm audit history exists for important actions.

### Non-functional tests

- Search performance with realistic data volume.
- Pagination for large tables.
- File upload limits and invalid file rejection.
- API authorization and validation.
- Desktop usability at common Windows screen sizes.
- Backend restart and database reconnection.
- Backup restoration.
- No secrets in Git history or application logs.

### Definition of done for every feature

A feature is not complete until:
1. Database migration exists where needed.
2. Backend logic and validation are implemented.
3. Authorization is enforced server-side.
4. Automated tests pass.
5. Swing UI is connected to the real API.
6. Loading, empty, success, and error states exist.
7. Documentation is updated.
8. No fake or hard-coded production data remains.

---

## 10. Repository and code organization

Use a simple multi-module repository:

```text
uber-maids-watch/
├── README.md
├── docs/
│   ├── requirements.md
│   ├── workflows.md
│   ├── database-design.md
│   ├── ui-guidelines.md
│   ├── security-and-privacy.md
│   ├── api-contract.md
│   └── deployment-guide.md
├── backend/
│   ├── pom.xml
│   └── src/
│       ├── main/java/.../
│       │   ├── config/
│       │   ├── security/
│       │   ├── common/
│       │   ├── workers/
│       │   ├── clients/
│       │   ├── services/
│       │   ├── bookings/
│       │   ├── placements/
│       │   ├── followups/
│       │   ├── replacements/
│       │   ├── payments/
│       │   └── reports/
│       └── main/resources/
│           └── db/migration/
├── desktop/
│   ├── pom.xml
│   └── src/
│       └── main/java/.../
│           ├── app/
│           ├── navigation/
│           ├── components/
│           ├── theme/
│           ├── api/
│           ├── models/
│           └── features/
├── website/
│   └── README.md
├── infra/
│   ├── docker-compose.yml
│   └── deployment/
└── .gitignore
```

The website implementation technology can be finalized after discovery. Keep it as a separate client of the Spring Boot API.

---

## 11. Instructions for Codex or OpenCode

The coding agent must work as a senior Java engineer and follow these rules:

1. Read this blueprint and the repository README before changing code.
2. Do not attempt to build every module in one prompt.
3. Start with Phase 0 assumptions and open questions. Clearly label assumptions.
4. Implement one phase or small vertical slice at a time.
5. Before coding, state the files and components it intends to create or modify.
6. After coding, run Maven tests and builds and report exact results.
7. Never claim a test passed unless it was actually executed successfully.
8. Never use fake success responses or hard-coded dashboard statistics.
9. Never put business rules in Swing button handlers.
10. Keep business logic in backend services and enforce permissions on the backend.
11. Use DTOs for API requests and responses; do not expose JPA entities directly.
12. Use Flyway migrations; do not rely on automatic schema creation in production.
13. Do not commit passwords, API keys, private documents, or production data.
14. Add tests for every important business rule.
15. Ask for clarification when a business policy affects money, worker eligibility, guarantee terms, privacy, or legal obligations.
16. Keep the application runnable after every phase.
17. Update documentation and a `docs/IMPLEMENTATION_STATUS.md` checklist after each completed task.
18. If a requirement is unclear, stop at that requirement and explain the decision needed instead of inventing a policy.

### 11.1 First prompt to give the coding agent

Copy this prompt into Codex or OpenCode after placing this blueprint in the repository:

> You are the senior Java software architect and implementation engineer for the UBER MAIDS WATCH Management System.
>
> Read `Uber_Maids_Watch_Development_Blueprint.md` completely before doing anything.
>
> Do not start implementing all modules immediately. First inspect the repository and produce:
> 1. A concise architecture summary.
> 2. A list of business rules that require confirmation from the owner.
> 3. A proposed repository structure.
> 4. A phased implementation checklist.
> 5. A risk list covering security, privacy, data integrity, and Swing responsiveness.
> 6. A list of dependencies and compatible Java/Spring versions, verified against current official documentation.
>
> Then implement only Phase 1: project foundation. Create the Spring Boot backend, PostgreSQL Docker Compose development setup, Flyway baseline, health endpoint, OpenAPI setup, and Java Swing desktop shell. The desktop shell must call the backend health endpoint through a dedicated API client and must not connect directly to PostgreSQL.
>
> Use Maven. Add automated tests. Run the build and tests. Report the commands executed, actual results, created files, unresolved issues, and how to run the application locally. Do not claim completion for anything that was not tested.
>
> Keep the design clean and professional. Use clear package boundaries, DTOs, service classes, repositories, configuration classes, and meaningful comments where they help explain non-obvious decisions.

### 11.2 Subsequent prompts

After Phase 1 is reviewed and working, give the agent one prompt at a time:

- **Phase 2:** "Implement authentication and role-based access control according to the blueprint. Include backend authorization tests and the Swing login and user-management screens."
- **Phase 3:** "Implement worker management, private document handling, verification checks, status history, and the corresponding Swing screens. Enforce permissions and add tests."
- **Phase 4:** "Implement client management, services/packages, enquiries, and booking workflows. Add database migrations, APIs, Swing screens, and tests."
- **Phase 5:** "Implement placements, configurable guarantee rules, daily follow-ups, incidents, replacement cases, backup worker selection, and the complete workflow tests."
- **Phase 6:** "Implement payment records, receipt references, operational reports, financial summaries, filters, CSV export, and role restrictions."
- **Phase 7:** "Implement the responsive public website as a separate client of the backend. Connect public enquiry and booking forms to the API. Do not expose private worker information."
- **Phase 8:** "Perform the full QA checklist, fix defects, verify permissions and backup restoration, and prepare deployment, rollback, training, and user documentation."

---

## 12. Decisions to confirm with Evelyn before production

These are discovery questions, not assumptions:

1. Is the free replacement guarantee exactly 14 calendar days? When does it start?
2. What conditions make a replacement eligible or ineligible?
3. What does daily tracking involve: phone follow-up, client confirmation, worker check-in, or another process?
4. What does same-day backup mean in practice, and during which hours/areas is it promised?
5. Which services and packages are currently offered, and what are their prices?
6. What payment methods are accepted?
7. Which staff members will use the system and what should each role access?
8. Should the website display worker profiles, or should it only collect client requests?
9. Which worker documents are collected, who verifies them, and how long should they be retained?
10. Does the business need SMS, WhatsApp, email, or in-app notifications in the first release?
11. What domain, logo, colors, and official contact details should be used?
12. What is the preferred hosting and ongoing support arrangement?

---

## 13. Recommended MVP release

To control cost and deliver value early, the first usable release should contain:

- Staff login and roles.
- Dashboard.
- Worker registration and verification.
- Client records.
- Service catalogue.
- Enquiry and booking management.
- Placement records.
- Follow-up tracking.
- Replacement case management.
- Basic payment records.
- Core operational reports.

The public website can launch alongside or immediately after the internal MVP, depending on budget and the owner's priorities. Advanced mobile apps, live GPS tracking, automated mobile-money integrations, and complex messaging integrations should be later phases unless discovery proves they are essential.

## 14. Final product principle

Build around the actual UBER MAIDS WATCH operating model:

**Verify → Train → Match → Place → Track → Support → Replace when eligible.**

Every screen, database table, report, and workflow should support one or more of these steps. The system should improve accountability and service quality while protecting the personal information of workers and clients.

**End of blueprint.**
