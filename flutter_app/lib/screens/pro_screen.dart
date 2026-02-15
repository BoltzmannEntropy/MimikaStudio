import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/settings_service.dart';

class ProScreen extends StatefulWidget {
  const ProScreen({super.key});

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  static const int _defaultTrialDays = 7;
  static const String _defaultPolarCheckoutUrl = 'https://polar.sh';
  static const String _defaultPolarPortalUrl = 'https://polar.sh';
  static const String _defaultLemonCheckoutUrl = 'https://lemonsqueezy.com';
  static const String _defaultLemonPortalUrl = 'https://lemonsqueezy.com';

  final SettingsService _settingsService = SettingsService();
  final TextEditingController _licenseController = TextEditingController();
  final TextEditingController _polarCheckoutUrlController =
      TextEditingController();
  final TextEditingController _polarPortalUrlController =
      TextEditingController();
  final TextEditingController _lemonCheckoutUrlController =
      TextEditingController();
  final TextEditingController _lemonPortalUrlController =
      TextEditingController();
  final FocusNode _licenseFocusNode = FocusNode();

  bool _isLoading = true;
  bool _isActivating = false;
  bool _isProActivated = false;
  int _trialDaysLeft = _defaultTrialDays;
  int _trialDurationDays = _defaultTrialDays;
  String _selectedProvider = 'polar';

  @override
  void initState() {
    super.initState();
    _loadLicenseState();
  }

  @override
  void dispose() {
    _licenseController.dispose();
    _polarCheckoutUrlController.dispose();
    _polarPortalUrlController.dispose();
    _lemonCheckoutUrlController.dispose();
    _lemonPortalUrlController.dispose();
    _licenseFocusNode.dispose();
    super.dispose();
  }

  bool _isValidProvider(String? value) {
    return value == 'polar' || value == 'lemonsqueezy';
  }

  String _providerLabel(String value) {
    return value == 'lemonsqueezy' ? 'LemonSqueezy' : 'Polar';
  }

  TextEditingController _checkoutControllerFor(String provider) {
    return provider == 'lemonsqueezy'
        ? _lemonCheckoutUrlController
        : _polarCheckoutUrlController;
  }

  TextEditingController _portalControllerFor(String provider) {
    return provider == 'lemonsqueezy'
        ? _lemonPortalUrlController
        : _polarPortalUrlController;
  }

  Future<void> _loadLicenseState() async {
    setState(() => _isLoading = true);

    try {
      final settings = await _settingsService.getAllSettings();

      final isPro =
          (settings['pro_activated'] ?? 'false').toLowerCase() == 'true';
      final trialDays =
          int.tryParse(settings['trial_duration_days'] ?? '') ??
          _defaultTrialDays;

      DateTime trialStart;
      final trialStartRaw = settings['trial_started_at'];
      if (trialStartRaw == null || trialStartRaw.trim().isEmpty) {
        trialStart = DateTime.now().toUtc();
        await _settingsService.setSetting(
          'trial_started_at',
          trialStart.toIso8601String(),
        );
      } else {
        trialStart =
            DateTime.tryParse(trialStartRaw)?.toUtc() ?? DateTime.now().toUtc();
      }

      if (!settings.containsKey('trial_duration_days')) {
        await _settingsService.setSetting(
          'trial_duration_days',
          '$_defaultTrialDays',
        );
      }
      if (!settings.containsKey('pro_activated')) {
        await _settingsService.setSetting('pro_activated', 'false');
      }
      final providerRaw = settings['license_provider'];
      final provider = _isValidProvider(providerRaw) ? providerRaw! : 'polar';
      if (!_isValidProvider(providerRaw)) {
        await _settingsService.setSetting('license_provider', provider);
      }

      final elapsedDays = DateTime.now().toUtc().difference(trialStart).inDays;
      final daysLeft = (trialDays - elapsedDays).clamp(0, trialDays);

      final licenseKey = settings['license_key'] ?? '';
      if (_licenseController.text.isEmpty && licenseKey.isNotEmpty) {
        _licenseController.text = licenseKey;
      }

      final polarCheckoutUrl =
          settings['polar_checkout_url'] ?? _defaultPolarCheckoutUrl;
      final polarPortalUrl =
          settings['polar_portal_url'] ?? _defaultPolarPortalUrl;
      final lemonCheckoutUrl =
          settings['lemonsqueezy_checkout_url'] ?? _defaultLemonCheckoutUrl;
      final lemonPortalUrl =
          settings['lemonsqueezy_portal_url'] ?? _defaultLemonPortalUrl;
      _polarCheckoutUrlController.text = polarCheckoutUrl;
      _polarPortalUrlController.text = polarPortalUrl;
      _lemonCheckoutUrlController.text = lemonCheckoutUrl;
      _lemonPortalUrlController.text = lemonPortalUrl;

      if (!mounted) return;
      setState(() {
        _isProActivated = isPro;
        _trialDurationDays = trialDays;
        _trialDaysLeft = daysLeft;
        _selectedProvider = provider;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load Pro license state: $e')),
      );
    }
  }

  Future<void> _activateLicense() async {
    final key = _licenseController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Enter a valid ${_providerLabel(_selectedProvider)} license key.',
          ),
        ),
      );
      return;
    }

    if (key.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('License key appears too short.')),
      );
      return;
    }

    setState(() => _isActivating = true);
    try {
      await _settingsService.setSetting('license_key', key);
      await _settingsService.setSetting('pro_activated', 'true');
      await _settingsService.setSetting('license_provider', _selectedProvider);
      await _settingsService.setSetting(
        'license_activated_at',
        DateTime.now().toUtc().toIso8601String(),
      );

      if (!mounted) return;
      setState(() {
        _isProActivated = true;
        _isActivating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'License activated (${_providerLabel(_selectedProvider)} mode).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isActivating = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to activate license: $e')));
    }
  }

  Future<void> _openUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invalid URL.')));
      }
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open URL.')));
    }
  }

  Future<void> _buyLicense(String provider) async {
    await _openUrl(_checkoutControllerFor(provider).text);
  }

  Future<void> _saveProviderUrls() async {
    await _settingsService.setSetting(
      'polar_checkout_url',
      _polarCheckoutUrlController.text.trim(),
    );
    await _settingsService.setSetting(
      'polar_portal_url',
      _polarPortalUrlController.text.trim(),
    );
    await _settingsService.setSetting(
      'lemonsqueezy_checkout_url',
      _lemonCheckoutUrlController.text.trim(),
    );
    await _settingsService.setSetting(
      'lemonsqueezy_portal_url',
      _lemonPortalUrlController.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Provider URLs saved.')));
  }

  Widget _buildProviderSelector() {
    return Wrap(
      spacing: 10,
      children: [
        ChoiceChip(
          label: const Text('Polar'),
          selected: _selectedProvider == 'polar',
          onSelected: (_) => setState(() => _selectedProvider = 'polar'),
        ),
        ChoiceChip(
          label: const Text('LemonSqueezy'),
          selected: _selectedProvider == 'lemonsqueezy',
          onSelected: (_) => setState(() => _selectedProvider = 'lemonsqueezy'),
        ),
      ],
    );
  }

  Widget _buildTrialBanner(BuildContext context) {
    if (_isProActivated) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(
              Icons.verified_rounded,
              color: Colors.green.shade700,
              size: 34,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Mimika Pro Active',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 6),
                  Text('All Pro features are unlocked on this device.'),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final trialEnded = _trialDaysLeft <= 0;
    final title = trialEnded ? 'Trial Ended' : 'Trial Ending Soon';
    final subtitle = trialEnded
        ? 'Your $_trialDurationDays-day trial has ended.'
        : 'You have $_trialDaysLeft day${_trialDaysLeft == 1 ? '' : 's'} left in your trial';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF1E8DD),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        runSpacing: 16,
        spacing: 16,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange.shade700,
                size: 42,
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () {
                  _licenseFocusNode.requestFocus();
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
                child: const Text(
                  'Enter License',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton(
                onPressed: () => _buyLicense('polar'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
                child: const Text(
                  'Buy with Polar',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton(
                onPressed: () => _buyLicense('lemonsqueezy'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
                child: const Text(
                  'Buy with LemonSqueezy',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.12),
                  ),
                  child: Icon(
                    Icons.workspace_premium_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Upgrade to Mimika Pro',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Buy from the app or website using Polar.sh or LemonSqueezy. Configure both checkout + portal URLs below, then activate your license.',
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _buyLicense('polar'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Upgrade via Polar'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () => _buyLicense('lemonsqueezy'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Upgrade via LemonSqueezy'),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () =>
                  _openUrl(_portalControllerFor(_selectedProvider).text),
              icon: const Icon(Icons.manage_accounts_rounded),
              label: Text('Open ${_providerLabel(_selectedProvider)} Portal'),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: const [
                _FeatureChip(
                  icon: Icons.support_agent_rounded,
                  label: 'Priority Support',
                ),
                _FeatureChip(
                  icon: Icons.sync_alt_rounded,
                  label: 'Dual Provider Activation',
                ),
                _FeatureChip(
                  icon: Icons.devices_rounded,
                  label: 'Multiple Devices',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivationCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Already have a license?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            _buildProviderSelector(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _licenseController,
                    focusNode: _licenseFocusNode,
                    decoration: InputDecoration(
                      hintText:
                          'Enter your ${_providerLabel(_selectedProvider)} license key',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _isActivating ? null : _activateLicense,
                  child: _isActivating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Activate'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () =>
                    _openUrl(_portalControllerFor(_selectedProvider).text),
                icon: const Icon(Icons.manage_accounts_rounded),
                label: Text('${_providerLabel(_selectedProvider)} Portal'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderConfigCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Licensing Provider Configuration',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _polarCheckoutUrlController,
              decoration: const InputDecoration(
                labelText: 'Polar Checkout URL',
                hintText: 'https://polar.sh/checkout/...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _polarPortalUrlController,
              decoration: const InputDecoration(
                labelText: 'Polar Customer Portal URL',
                hintText: 'https://polar.sh/portal/...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lemonCheckoutUrlController,
              decoration: const InputDecoration(
                labelText: 'LemonSqueezy Checkout URL',
                hintText: 'https://lemonsqueezy.com/checkout/...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _lemonPortalUrlController,
              decoration: const InputDecoration(
                labelText: 'LemonSqueezy Customer Portal URL',
                hintText: 'https://app.lemonsqueezy.com/my-orders/...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _saveProviderUrls,
              child: const Text('Save Provider URLs'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadLicenseState,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildTrialBanner(context),
                  const SizedBox(height: 18),
                  if (!_isProActivated) ...[
                    _buildProCard(context),
                    const SizedBox(height: 18),
                  ],
                  _buildActivationCard(context),
                  const SizedBox(height: 18),
                  _buildProviderConfigCard(),
                ],
              ),
            ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
