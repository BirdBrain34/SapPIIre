CREATE TABLE dashboard_widget_configs (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  template_id text NOT NULL REFERENCES form_templates(template_id) ON DELETE CASCADE,
  field_name text NOT NULL,
  field_label text NOT NULL,
  chart_type text NOT NULL CHECK (chart_type IN ('bar', 'pie', 'counter', 'hbar', 'table')),
  display_order int DEFAULT 0,
  created_by text,
  updated_at timestamptz DEFAULT now(),
  UNIQUE(template_id, field_name)
);