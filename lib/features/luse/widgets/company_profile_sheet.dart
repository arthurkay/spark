import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/widgets/sheet_keyboard_padding.dart';
import '../models/luse_company_profile.dart';
import '../providers/luse_provider.dart';

class CompanyProfileSheet extends ConsumerWidget {
  const CompanyProfileSheet({super.key, required this.symbol});

  final String symbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(luseCompanyProfileProvider(symbol));

    return SheetKeyboardPadding(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: profileAsync.when(
            loading: () => const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SizedBox(
              height: 200,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.triangleAlert, size: 32)
                        .iconMutedForeground,
                    const Gap(8),
                    Text('Failed to load profile').muted,
                    const Gap(12),
                    PrimaryButton(
                      onPressed: () =>
                          ref.invalidate(luseCompanyProfileProvider(symbol)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
            data: (profile) {
              if (profile == null) {
                return SizedBox(
                  height: 200,
                  child: Center(child: Text('No profile data').muted),
                );
              }
              return _ProfileContent(profile: profile);
            },
          ),
        ),
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({required this.profile});

  final LuseCompanyProfile profile;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(profile.name).h4,
          const Gap(4),
          if (profile.sector != null) ...[
            Row(
              children: [
                const Icon(LucideIcons.building, size: 14).iconMutedForeground,
                const Gap(6),
                Text(profile.sector!).small.muted,
              ],
            ),
            const Gap(8),
          ],
          if (profile.description.isNotEmpty) ...[
            Text(profile.description).small,
            const Gap(16),
          ],
          _InfoSection(profile: profile),
          if (profile.reports.isNotEmpty) ...[
            const Gap(16),
            _ReportsSection(reports: profile.reports),
          ],
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.profile});

  final LuseCompanyProfile profile;

  @override
  Widget build(BuildContext context) {
    final items = <_InfoItem>[];
    if (profile.listingDate != null) {
      items.add(_InfoItem(label: 'Listed', value: profile.listingDate!));
    }
    if (profile.yearEnd != null) {
      items.add(_InfoItem(label: 'Year End', value: profile.yearEnd!));
    }
    if (profile.address != null) {
      items.add(_InfoItem(label: 'Address', value: profile.address!));
    }
    if (profile.phone != null) {
      items.add(_InfoItem(label: 'Phone', value: profile.phone!));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items.map((item) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 80,
                  child: Text(item.label).xSmall.muted,
                ),
                Expanded(child: Text(item.value).small),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _InfoItem {
  const _InfoItem({required this.label, required this.value});

  final String label;
  final String value;
}

class _ReportsSection extends StatelessWidget {
  const _ReportsSection({required this.reports});

  final List<LuseCompanyReport> reports;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Annual Reports').small.semiBold,
        const Gap(8),
        ...reports.take(10).map((report) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: GestureDetector(
              onTap: () async {
                final uri = Uri.parse(report.url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.muted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.fileText, size: 14)
                        .iconMutedForeground,
                    const Gap(8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(report.title).xSmall,
                          if (report.date != null)
                            Text(report.date!).xSmall.muted,
                        ],
                      ),
                    ),
                    const Icon(LucideIcons.externalLink, size: 12)
                        .iconMutedForeground,
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
