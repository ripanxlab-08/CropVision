import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/supabase_service.dart';
import '../widgets/gradient_app_bar.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;

  // Kept as a plain constant rather than reading it via a package like
  // package_info_plus - avoids adding another native plugin dependency
  // to an already fragile Android/NDK build setup for a single version
  // string. Update this to match pubspec.yaml's version manually.
  static const String _appVersion = '0.1.0';

  @override
  Widget build(BuildContext context) {
    final service = context.read<SupabaseService>();
    final email = service.currentUser?.email ?? 'Not signed in';

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: const GradientAppBar(title: 'Settings'),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // Profile header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: AppColors.canopy,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Account', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(email, style: const TextStyle(color: AppColors.inkMuted, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const _SettingsDivider(),
          const _SettingsSectionLabel('Preferences'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined, color: AppColors.inkMuted),
            title: const Text('Reminder notifications'),
            subtitle: const Text('Get notified about crop calendar reminders', style: TextStyle(fontSize: 12.5)),
            value: _notificationsEnabled,
            activeThumbColor: AppColors.neon,
            onChanged: (v) => setState(() => _notificationsEnabled = v),
          ),
          const _SettingsDivider(),
          const _SettingsSectionLabel('Data'),
          ListTile(
            leading: const Icon(Icons.history, color: AppColors.inkMuted),
            title: const Text('Diagnosis history'),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => Navigator.pushNamed(context, '/history'),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined, color: AppColors.inkMuted),
            title: const Text('Crop calendar'),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => Navigator.pushNamed(context, '/calendar'),
          ),
          const _SettingsDivider(),
          const _SettingsSectionLabel('About'),
          const ListTile(
            leading: Icon(Icons.info_outline, color: AppColors.inkMuted),
            title: Text('App version'),
            trailing: Text(_appVersion, style: TextStyle(color: AppColors.inkMuted)),
          ),
          const ListTile(
            leading: Icon(Icons.eco_outlined, color: AppColors.inkMuted),
            title: Text('About CropVision'),
            subtitle: Text(
              'AI-powered crop disease detection with real-time severity staging.',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
          const _SettingsDivider(),
          Padding(
            padding: const EdgeInsets.all(20),
            child: OutlinedButton.icon(
              onPressed: () async {
                await service.signOut();
                if (context.mounted) {
                  Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.rust,
                side: const BorderSide(color: AppColors.rust),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.logout),
              label: const Text('Log Out'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  final String text;
  const _SettingsSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.inkMuted.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, color: AppColors.darkSurfaceElevated);
  }
}
