# 08. Web Staff Feature Traceability Matrix

## 1. Scope

This matrix traces CSWD web-platform capabilities to implementation surfaces and data artifacts. It is intended for audience-specific validation of staff and administrative functionality.

The web tier implements a **layered architecture** with clear separation of concerns:
- **Controllers** (`lib/web/controllers/`): Business logic, state management, service coordination
- **Screens** (`lib/web/screen/`): UI rendering, user interaction handling, navigation
- **Components** (`lib/web/components/`): Specialized analytics and chart components
- **Widgets** (`lib/web/widgets/`): Reusable UI components (form cards, dialogs, navigation)
- **Utilities** (`lib/web/utils/`): Shared helpers (page transitions, navigation routing)

This architecture ensures reusability, testability, and maintainability across the web surface.

## 2. Traceability Matrix

| Web Feature | Staff Intent | Primary Web or Service Modules | Primary Tables | Security or Governance Outcome |
| --- | --- | --- | --- | --- |
| Role-sensitive login policy | Authenticate by correct credential mode | Screen: `web_login_screen.dart` → Service: `WebAuthService.login` | `staff_accounts`, `staff_profiles` | Enforces account state and role-aware identity resolution |
| Pending staff registration | Submit staff account request | Screen: `web_signup_screen.dart` → Service: `WebSignupService.createPendingStaffAccount` | `staff_accounts`, `staff_profiles` | Controlled onboarding with `requested_role` and pending state |
| Account approval or rejection | Governance of requested staff roles | Controller: `ManageStaffController` → Screen: `manage_staff_screen.dart` → Service: `StaffAdminService` | `staff_accounts` | Role governance and lifecycle control |
| Admin account creation (extended) | Superadmin creates operational admin accounts | Controller: `ManageStaffController` → Screen: `create_staff_screen.dart` → Service: `StaffAdminService` | `staff_accounts`, `staff_profiles` | Institutional provisioning without ad hoc DB edits |
| New-staff OTP setup | First-time staff password bootstrap | Screen: `new_staff_setup_screen.dart` → Service: `StaffEmailService`, `WebAuthService` | `staff_accounts` | Stronger first-login control and setup traceability |
| Staff password reset OTP | Recover staff access securely | Screen: `forgot_password_screen.dart` → Service: `StaffEmailService` | `staff_accounts`, `staff_password_reset_otp` | Reduced credential compromise and recovery friction |
| Manage Forms session lifecycle | Create, monitor, and close intake sessions | Controller: `ManageFormsController` → Screen: `manage_forms_screen.dart` → Service: `SubmissionService` | `form_submission` | Session-bounded intake operations and expiry containment; Zero-Knowledge Staging ensures no plaintext persistence |
| Secured autofill consumption | Receive decrypted mobile payload into staff form | Controller: `ManageFormsController.decryptStagingSubmission` → Screen: `manage_forms_screen.dart` → Service: `SubmissionService.fetchDecryptedStagingSubmission` → Edge Function: `serve-submission-for-review` | `form_submission`, `submission_field_values` | Encrypted Envelope → Edge Decryption → In-Memory Delivery; plaintext never written to database |
| Finalize applicant records with encryption | Commit reviewed data to server-encrypted archive | Controller: `ManageFormsController` → Screen: `manage_forms_screen.dart` → Service: `SubmissionService.upsertClientSubmissionSecure` | `client_submissions` | Server-side AES-256-GCM encrypted intake records with session linkage |
| Applicant review and edit workflows | Access and manage historical records | Controller: `ApplicantsController` → Screen: `applicants_screen.dart` → Service: analytics/submission services, `SubmissionService.batchDecryptSubmissions` | `client_submissions`, `form_templates` | Staff productivity with controlled record mutation; 5-10x faster loading via batch decryption Edge Function |
| Dynamic form builder | Author and evolve form templates | Controller: `FormBuilderScreenController` → Screen: `form_builder_screen.dart` + Widgets (field cards, section headers, etc.) → Service: `FormBuilderService` | `form_templates`, `form_sections`, `form_fields`, `form_field_options`, `form_field_conditions` | Schema-less form evolution and institutional agility |
| Form builder unsaved changes detection | Prevent accidental loss of template edits | Controller: `FormBuilderScreenController` (change tracking) → Screen: `form_builder_screen.dart` (WillPopScope dialog) | `form_templates` | User intent protection with explicit save/discard dialog |
| Template and field lifecycle notifications | Broadcast form infrastructure changes to all clients | Service: `FormTemplateNotificationService` → Screen: `form_builder_screen.dart` (notification handler) | `form_template_notifications` | Synchronized awareness of template changes across all platforms |
| Publish and mobile push workflow | Control form release lifecycle | Controller: `FormBuilderScreenController` → Service: `FormBuilderService.publishTemplate/pushToMobile` | `form_templates` | Controlled deployment semantics |
| Dashboard analytics | Monitor workload and intake trends | Controller: `DashboardController` → Screen: `dashboard_screen.dart` + Components: `AutoChartBuilder`, `IntakeChartWidgets`, `EnhancedChartWidgets` → Service: `DashboardAnalyticsService` (with `fetchSubmissionsByFormTypeForWorker` for worker drill-down, `batchDecryptSubmissions` for efficient data loading) | `form_submission`, `client_submissions`, `staff_profiles` | Operational visibility and planning support with interactive worker drill-down, client search, configurable card elevation, and time-frame filtering |
| Display session broadcasting | Project active session state to monitor | Screen: `customer_display_screen.dart` → Service: `DisplaySessionService` | `display_sessions`, `form_submission` | Frontline coordination and queue transparency |
| Audit log monitoring | Review sensitive admin and auth events | Screen: `audit_logs_screen.dart` → Service: `AuditLogService` (with action type filtering) | `audit_logs` | Forensic accountability and compliance support; submission decryption events automatically logged by `decrypt-submission-data` Edge Function |
| Deactivate or reactivate staff accounts | Enforce access lifecycle decisions | Controller: `ManageStaffController` → Screen: `manage_staff_screen.dart` → Service: `WebAuthService` | `staff_accounts` | Immediate revocation and reinstatement governance |

## 3. Validation Notes

1. Web traceability should be demonstrated end-to-end: staff login, form builder unsaved changes test (controller state tracking), template notification receipt, session creation with ManageFormsController coordination, mobile payload arrival, finalize to encrypted `client_submissions`, and audit/event visibility.
2. Governance evidence should include at least one pending-account approval via ManageStaffController and one admin-created account setup path.
3. Dynamic-form evidence should include draft, publish, and push-to-mobile lifecycle transitions via FormBuilderScreenController, with template notifications triggering on each transition.
4. Client submissions encryption should be verified with `data_encryption_version=1`, Base64-encoded `data_iv`, and encrypted `data` column in finalized records.
5. Architecture validation should trace at least three features through their complete layer flow: Controller → Screen + Widgets → Service.
