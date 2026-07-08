import 'package:flutter/material.dart';

import 'package:sappiire/web/utils/page_transitions.dart';
import 'package:sappiire/web/screen/applicants_screen.dart';
import 'package:sappiire/web/screen/audit_logs_screen.dart';
import 'package:sappiire/web/screen/create_staff_screen.dart';
import 'package:sappiire/web/screen/dashboard_screen.dart';
import 'package:sappiire/web/screen/form_builder_screen.dart';
import 'package:sappiire/web/screen/manage_forms_screen.dart';
import 'package:sappiire/web/screen/manage_staff_screen.dart';

class WebNavigator {
  static void go(
    BuildContext context,
    String screenPath, {
    required String cswdId,
    required String role,
    required String displayName,
  }) {
    Widget? nextScreen;

    switch (screenPath) {
      case 'Dashboard':
        nextScreen = DashboardScreen(
          cswd_id: cswdId,
          role: role,
          displayName: displayName,
        );
        break;
      case 'Forms':
        nextScreen = ManageFormsScreen(
          cswd_id: cswdId,
          role: role,
          displayName: displayName,
        );
        break;
      case 'Staff':
        if (role != 'superadmin') return;
        nextScreen = ManageStaffScreen(
          cswd_id: cswdId,
          role: role,
          displayName: displayName,
        );
        break;
      case 'CreateStaff':
        if (role != 'superadmin') return;
        nextScreen = CreateStaffScreen(
          cswd_id: cswdId,
          role: role,
          displayName: displayName,
        );
        break;
      case 'Applicants':
        nextScreen = ApplicantsScreen(
          cswd_id: cswdId,
          role: role,
          displayName: displayName,
        );
        break;
      case 'AuditLogs':
        if (role != 'superadmin') return;
        nextScreen = AuditLogsScreen(
          cswd_id: cswdId,
          role: role,
          displayName: displayName,
        );
        break;
      case 'FormBuilder':
        if (role != 'superadmin') return;
        nextScreen = FormBuilderScreen(
          cswd_id: cswdId,
          role: role,
          displayName: displayName,
        );
        break;
      default:
        return;
    }

    Navigator.of(context).pushReplacement(
      ContentFadeRoute(page: nextScreen),
    );
  }
}
