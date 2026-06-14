import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/user_profile.dart';
import '../../core/state/providers.dart';
import '../../core/widgets/precise_field.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;

  // Collected answers (sensible defaults so sliders start mid-range).
  final _nameController = TextEditingController();
  Sex _sex = Sex.male;
  double _age = 28;
  double _heightCm = 168;
  double _weightKg = 70;
  ActivityLevel _activity = ActivityLevel.light;
  Goal _goal = Goal.lose;

  UserProfile get _draft => UserProfile(
        name: _nameController.text.trim().isEmpty
            ? 'there'
            : _nameController.text.trim(),
        sex: _sex,
        age: _age.round(),
        heightCm: _heightCm,
        weightKg: _weightKg,
        activity: _activity,
        goal: _goal,
      );

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < 4) {
      _pageController.nextPage(
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Future<void> _finish() async {
    await ref.read(profileProvider.notifier).save(_draft);
    if (mounted) context.go('/today');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: LinearProgressIndicator(
                value: (_page + 1) / 5,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _welcomePage(),
                  _bodyPage(),
                  _activityPage(),
                  _goalPage(),
                  _resultPage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frame({
    required String title,
    String? subtitle,
    required Widget child,
    required VoidCallback onContinue,
    String continueLabel = 'Continue',
  }) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 24),
          Expanded(child: child),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onContinue, child: Text(continueLabel)),
          ),
        ],
      ),
    );
  }

  Widget _welcomePage() {
    return _frame(
      title: 'Welcome to CalorieLens 📸',
      subtitle: 'Snap a photo of any meal — even nasi lemak — and we break it down for you. Let\'s set up your targets first.',
      onContinue: _next,
      continueLabel: 'Get started',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'What should we call you?'),
            textCapitalization: TextCapitalization.words,
          ),
        ],
      ),
    );
  }

  Widget _bodyPage() {
    return _frame(
      title: 'About you',
      subtitle: 'We use this to estimate how much energy your body burns.',
      onContinue: _next,
      child: ListView(
        children: [
          SegmentedButton<Sex>(
            segments: const [
              ButtonSegment(value: Sex.male, label: Text('Male')),
              ButtonSegment(value: Sex.female, label: Text('Female')),
            ],
            selected: {_sex},
            onSelectionChanged: (s) => setState(() => _sex = s.first),
          ),
          const SizedBox(height: 24),
          PreciseField(
            label: 'Age',
            value: _age,
            min: 14,
            max: 90,
            unit: 'years',
            onChanged: (v) => setState(() => _age = v),
          ),
          PreciseField(
            label: 'Height',
            value: _heightCm,
            min: 130,
            max: 210,
            unit: 'cm',
            onChanged: (v) => setState(() => _heightCm = v),
          ),
          PreciseField(
            label: 'Weight',
            value: _weightKg,
            min: 35,
            max: 180,
            step: 0.1,
            decimals: 1,
            unit: 'kg',
            onChanged: (v) => setState(() => _weightKg = v),
          ),
        ],
      ),
    );
  }

  Widget _activityPage() {
    return _frame(
      title: 'How active are you?',
      subtitle: 'Outside of deliberate exercise too — delivery riders burn more than desk workers.',
      onContinue: _next,
      child: ListView(
        children: ActivityLevel.values
            .map((level) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _choiceCard(
                    selected: _activity == level,
                    title: level.label,
                    subtitle: level.description,
                    onTap: () => setState(() => _activity = level),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _goalPage() {
    return _frame(
      title: 'What\'s your goal?',
      onContinue: _next,
      child: ListView(
        children: Goal.values
            .map((goal) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _choiceCard(
                    selected: _goal == goal,
                    title: goal.label,
                    subtitle: switch (goal) {
                      Goal.lose => 'Steady, sustainable deficit (~0.4 kg/week)',
                      Goal.maintain => 'Hold your current weight',
                      Goal.gain => 'Lean surplus for muscle growth',
                    },
                    onTap: () => setState(() => _goal = goal),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _choiceCard({
    required bool selected,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: selected ? scheme.primaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_circle, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultPage() {
    final p = _draft;
    final scheme = Theme.of(context).colorScheme;
    return _frame(
      title: 'Your daily targets',
      subtitle:
          'Based on Mifflin-St Jeor — the same formula dietitians use. You can adjust these any time in Profile.',
      onContinue: _finish,
      continueLabel: 'Start tracking',
      child: ListView(
        children: [
          Card(
            color: scheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text('${p.kcalTarget.round()}',
                      style: Theme.of(context)
                          .textTheme
                          .displayMedium
                          ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.onPrimaryContainer)),
                  Text('kcal per day',
                      style: TextStyle(color: scheme.onPrimaryContainer)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _macroCard('Protein', '${p.proteinTargetG.round()} g', '🍗'),
              const SizedBox(width: 8),
              _macroCard('Carbs', '${p.carbsTargetG.round()} g', '🍚'),
              const SizedBox(width: 8),
              _macroCard('Fat', '${p.fatTargetG.round()} g', '🥑'),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Text('💧', style: TextStyle(fontSize: 24)),
              title: const Text('Water'),
              trailing: Text('${(p.waterTargetMl / 1000).toStringAsFixed(1)} L',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _macroCard(String label, String value, String emoji) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 4),
              Text(value,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
