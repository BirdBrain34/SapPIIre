# 03. V2 Dynamic Form Architecture

## 1. V2 Rationale

The Dynamic Form Builder is the project's principal future-proofing mechanism. It externalizes form structure into relational metadata so that CSWD can evolve intake artifacts without recurrent backend schema redesign. This module extends, but does not replace, the manuscript core of secured hybrid autofill.

## 2. Metadata-Driven Form Domain

### 2.1 Template Root (`form_templates`)

`form_templates` defines top-level form identity and publication state:

1. Naming and description: `form_name`, `form_desc`.
2. Activation and workflow: `is_active`, `status` (`draft`, `published`, `pushed_to_mobile`).
3. Governance metadata: `created_by`, `published_at`, `pushed_to_mobile_at`.
4. Intake reference policy: `form_code`, `reference_prefix`, `reference_format`, `requires_reference`, `reference_counter`.
5. UI extensibility: `theme_config`, `popup_enabled`, `popup_subtitle`, `popup_description`.

### 2.2 Section Layer (`form_sections`)

`form_sections` partitions templates into ordered logical groups (`section_order`) and supports collapsible behavior through `is_collapsible`.

### 2.3 Field Layer (`form_fields`)

`form_fields` carries field-level semantics:

1. Machine and display identity: `field_name`, `field_label`.
2. Type system: `field_type`.
3. Validation and defaults: `validation_rules`, `default_value`, `is_required`.
4. Ordering and UX: `field_order`, `placeholder`.
5. Semantic mapping: `autofill_source`, `canonical_field_key`.
6. Hierarchy: `parent_field_id` for nested or composite field structures.

### 2.4 Option and Condition Layers

1. `form_field_options` stores dropdown/choice sets with order and default flags.
2. `form_field_conditions` stores conditional logic edges (`trigger_field_id`, `trigger_value`, `action`).

Together, these five tables (`form_templates` -> `form_sections` -> `form_fields` + options + conditions) define a complete declarative form graph.

## 3. Runtime Rendering Architecture

### 3.1 Dynamic UI Synthesis

The rendering engine consumes metadata and materializes controls at runtime:

1. Mobile mode renders paginated sections.
2. Web mode renders full section stacks for caseworker review.

This shared renderer architecture enforces cross-channel consistency of data semantics and validation behavior.

### 3.2 State and Rule Engine

`FormStateController` manages dynamic execution semantics:

1. Value state graph and notifier orchestration.
2. Conditional visibility evaluation using trigger maps.
3. Computed-field recalculation.
4. JSON import/export fidelity for `form_submission` and `client_submissions` workflows.

### 3.3 Conditional and Computed Intelligence

V2 supports conditional branching and computed formulas, including table aggregate functions (for example, `SUM_COLUMN`). Formula normalization bridges legacy human labels to machine-safe keys, preserving backward compatibility for older templates.

## 4. Data Persistence Coupling

The dynamic metadata domain is coupled to storage layers through stable foreign keys:

1. `user_field_values.field_id` -> `form_fields.field_id`
2. `submission_field_values.field_id` -> `form_fields.field_id`
3. `submission_field_values.submission_id` -> `form_submission.id`
4. `client_submissions.template_id` -> `form_templates.template_id`

This coupling ensures that template-driven UI evolution remains compatible with both user-owned reusable values and session-specific submissions.

## 5. Comprehensive Feature Inventory (Core and Extended)

### 5.1 Manuscript Core Features

1. Mobile PII management with protected at-rest storage.
2. Hybrid cryptosystem (AES payload encryption, RSA key wrapping).
3. QR handshake protocol for mobile-to-web transfer.
4. Secured autofill engine via backend decryption and session hydration.
5. CSWD staff dashboard for intake processing and history management.
6. Basic role-based access through `staff_accounts` and `staff_profiles`.

### 5.2 V2 and Beyond-Manuscript Features

1. Dynamic form template builder (`form_templates`, `form_sections`, `form_fields`).
2. Dynamic form rendering across mobile and web channels.
3. Conditional logic engine (`form_field_conditions`).
4. OCR information scanner using camera + ML Kit text recognition.
5. OTP verification (`phone_otp`, email OTP and staff reset flows).
6. Advanced staff governance (`requested_role`, `account_status`, activation lifecycle).
7. Display session synchronization (`display_sessions`) for station-linked monitors.
8. Audit observability (`audit_logs`) for sensitive operational events.

## 6. Scalability Implications for CSWD

The V2 architecture enables:

1. New form onboarding without table-per-form redesign.
2. Controlled publication-to-mobile deployment pipeline.
3. Semantic cross-template autofill through canonical keys.
4. Preservation of historical submissions as templates evolve.

This positions the system as a configurable intake platform rather than a single-form implementation.

## 7. Governance Notes from Current Schema Context

1. Template status check constraints currently include `draft`, `published`, and `pushed_to_mobile`; if archival states are required in production workflows, the status domain should be explicitly expanded.
2. Dynamic metadata changes should be audited with actor attribution to sustain administrative accountability.
3. Condition and formula validation tooling is recommended before publication to prevent runtime rule conflicts.
