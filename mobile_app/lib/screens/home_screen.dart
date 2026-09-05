import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.read<SupabaseService>();

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: RefreshIndicator(
        onRefresh: () async {},
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header - no longer a giant gradient banner, just a
              // simple top bar. The visual weight moves to the health
              // overview card below instead, which now carries the
              // actual information rather than the header carrying
              // decoration.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Field Dashboard', style: Theme.of(context).textTheme.headlineSmall),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.settings_outlined, color: AppColors.inkMuted),
                            onPressed: () => Navigator.pushNamed(context, '/settings'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.logout, color: AppColors.inkMuted),
                            onPressed: () async {
                              await service.signOut();
                              if (context.mounted) {
                                Navigator.pushReplacementNamed(context, '/login');
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: FutureBuilder<DashboardStats>(
                  future: service.fetchDashboardStats(),
                  builder: (context, snapshot) {
                    return _HealthOverviewCard(stats: snapshot.data, loading: !snapshot.hasData);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Quick actions', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 14),
                    // Bento layout: one large primary action, three
                    // smaller secondary actions - not a uniform grid.
                    // Diagnose Leaf is the thing someone opens this app
                    // to do most often, so it gets the visual weight.
                    _HeroActionCard(
                      icon: Icons.camera_alt,
                      label: 'Diagnose Leaf',
                      subtitle: 'Take or upload a photo for instant analysis',
                      color: AppColors.canopy,
                      onTap: () => Navigator.pushNamed(context, '/capture'),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _SmallActionCard(
                            icon: Icons.history,
                            label: 'History',
                            color: AppColors.rust,
                            onTap: () => Navigator.pushNamed(context, '/history'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SmallActionCard(
                            icon: Icons.calendar_month,
                            label: 'Calendar',
                            color: AppColors.chlorotic,
                            onTap: () => Navigator.pushNamed(context, '/calendar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SmallActionCard(
                            icon: Icons.smart_toy,
                            label: 'Assistant',
                            color: AppColors.neon,
                            onTap: () => Navigator.pushNamed(context, '/assistant'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Replaces the old "3 identical number boxes" with one card that
/// actually visualizes the healthy/needs-attention split as a
/// proportion (a segmented bar), not just three disconnected counts -
/// this answers "how is my field doing overall" at a glance instead of
/// making the farmer do the subtraction themselves.
class _HealthOverviewCard extends StatelessWidget {
  final DashboardStats? stats;
  final bool loading;
  const _HealthOverviewCard({required this.stats, required this.loading});

  @override
  Widget build(BuildContext context) {
    final total = stats?.totalScans ?? 0;
    final healthy = stats?.healthyCount ?? 0;
    final needsAttention = stats?.needsAttentionCount ?? 0;
    final healthyFraction = total == 0 ? 0.5 : healthy / total;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                loading ? '—' : '$total',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 36),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text('scans this season', style: TextStyle(color: AppColors.inkMuted, fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 12,
              child: loading
                  ? Container(color: AppColors.darkSurfaceElevated)
                  : Row(
                      children: [
                        if (healthy > 0)
                          Expanded(flex: (healthyFraction * 100).round().clamp(1, 100), child: Container(color: AppColors.canopy)),
                        if (needsAttention > 0)
                          Expanded(
                            flex: ((1 - healthyFraction) * 100).round().clamp(1, 100),
                            child: Container(color: AppColors.rust),
                          ),
                        if (total == 0) Expanded(child: Container(color: AppColors.darkSurfaceElevated)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _LegendDot(color: AppColors.canopy, label: '$healthy healthy'),
              const SizedBox(width: 20),
              _LegendDot(color: AppColors.rust, label: '$needsAttention needs attention'),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: AppColors.inkMuted, fontSize: 13)),
      ],
    );
  }
}

/// The single large primary action - full width, more generous
/// padding, an icon watermark ghosted in the background for texture,
/// and a subtitle explaining what happens when tapped. Structurally
/// distinct from the small cards below, not just a bigger version of
/// the same thing.
class _HeroActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _HeroActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.35)!],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            bottom: -20,
            child: Icon(icon, size: 140, color: Colors.white.withValues(alpha: 0.08)),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 32, color: Colors.white),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 19)),
                          const SizedBox(height: 4),
                          Text(subtitle,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Secondary actions - compact, icon-first, no gradient (visually
/// quieter than the hero card on purpose, so the hierarchy reads
/// correctly at a glance).
class _SmallActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SmallActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
            child: Column(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(height: 8),
                Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
