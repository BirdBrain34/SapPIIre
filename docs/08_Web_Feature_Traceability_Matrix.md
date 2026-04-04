# 08. Web Staff Feature Traceability Matrix

## 1. Scope

This matrix traces CSWD web-platform capabilities to implementation surfaces and data artifacts. It is intended for audience-specific validation of staff and administrative functionality.

## 2. Traceability Matrix

| Web Feature | Staff Intent | Primary Web or Service Modules | Primary Tables | Security or Governance Outcome |
| --- | --- | --- | --- | --- |
| Role-sensitive login policy | Authenticate by correct credential mode | `web_login_screen.dart`, `WebAuthService.login` | `staff_accounts`, `staff_profiles` | Enforces account state and role-aware identity resolution |
| Pending staff registration | Submit staff account request | `web_signup_screen.dart`, `WebSignupService.createPendingStaffAccount` | `staff_accounts`, `staff_profiles` | Controlled onboarding with `requested_role` and pending state |
| Account approval or rejection | Governance of requested staff roles | `manage_staff_screen.dart`, `StaffAdminService.approveAccount/rejectAccount` | `staff_accounts` | Role governance and lifecycle control |
| Admin account creation (extended) | Superadmin creates operational admin accounts | `create_staff_screen.dart`, `StaffAdminService.createAdminStaffAccount` | `staff_accounts`, `staff_profiles` | Institutional provisioning without ad hoc DB edits |
| New-staff OTP setup | First-time staff password bootstrap | `new_staff_setup_screen.dart`, `StaffEmailService.verifyPendingSetupOtp`, `WebAuthService.resetPasswordWithOtp` | `staff_accounts` | Stronger first-login control and setup traceability |
| Staff password reset OTP | Recover staff access securely | `forgot_password_screen.dart`, `StaffEmailService.sendPasswordResetOtp/verifyPasswordResetOtp` | `staff_accounts`, `staff_password_reset_otp` | Reduced credential compromise and recovery friction |
| Manage Forms session lifecycle | Create, monitor, and close intake sessions | `manage_forms_screen.dart`, `SubmissionService` | `form_submission` | Session-bounded intake operations and expiry containment |
| Secured autofill consumption | Receive decrypted mobile payload into staff form | `manage_forms_screen.dart`, Edge function integration | `form_submission`, `submission_field_values` | Controlled decrypt-to-form runtime transition |
| Finalize applicant records | Commit reviewed data to final archive | `manage_forms_screen.dart`, `SubmissionService.upsertClientSubmission` | `client_submissions` | Durable intake records with session linkage |
| Applicant review and edit workflows | Access and manage historical records | `applicants_screen.dart`, analytics services | `client_submissions`, `form_templates` | Staff productivity with controlled record mutation |
| Dynamic form builder | Author and evolve form templates | `form_builder_screen.dart`, `FormBuilderService` | `form_templates`, `form_sections`, `form_fields`, `form_field_options`, `form_field_conditions` | Schema-less form evolution and institutional agility |
| Publish and mobile push workflow | Control form release lifecycle | `FormBuilderService.publishTemplate/pushToMobile` | `form_templates` | Controlled deployment semantics |
| Dashboard analytics | Monitor workload and intake trends | `dashboard_screen.dart`, `DashboardAnalyticsService` | `form_submission`, `client_submissions`, `staff_profiles` | Operational visibility and planning support |
| Display session broadcasting | Project active session state to monitor | `customer_display_screen.dart`, `DisplaySessionService` | `display_sessions`, `form_submission` | Frontline coordination and queue transparency |
| Audit log monitoring | Review sensitive admin and auth events | `audit_logs_screen.dart`, `AuditLogService` | `audit_logs` | Forensic accountability and compliance support |
| Deactivate or reactivate staff accounts | Enforce access lifecycle decisions | `manage_staff_screen.dart`, `WebAuthService.deactivate/reactivate` | `staff_accounts` | Immediate revocation and reinstatement governance |

## 3. Validation Notes

1. Web traceability should be demonstrated end-to-end: staff login, session creation, mobile payload arrival, finalize to `client_submissions`, and audit/event visibility.
2. Governance evidence should include at least one pending-account approval and one admin-created account setup path.
3. Dynamic-form evidence should include draft, publish, and push-to-mobile lifecycle transitions.
