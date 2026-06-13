import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/data/food_search_api.dart';
import '../../core/data/repositories.dart';
import '../../core/models/diary_entry.dart';
import '../../core/models/food.dart';
import '../../core/state/providers.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialMeal});

  /// Pre-selected meal when opened from a diary section's "+".
  final String? initialMeal;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  int _requestSeq = 0;
  List<Food> _results = const [];
  String _query = '';
  bool _loading = false;
  bool _offline = false;
  bool _estimating = false;

  @override
  void initState() {
    super.initState();
    _runSearch(''); // regional favourites before the first keystroke
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Debounce keystrokes so we hit the backend once the user pauses.
  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      _runSearch('');
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    final seq = ++_requestSeq; // guard against out-of-order responses
    final result = await ref.read(foodSearchApiProvider).search(query);
    if (!mounted || seq != _requestSeq) return;
    setState(() {
      _results = result.foods;
      _offline = result.offline;
      _query = query.trim();
      _loading = false;
    });
  }

  /// Ask Gemini to estimate a dish no database carries (ban mee, loh mee…),
  /// then open the log sheet with the result.
  Future<void> _estimateWithAi() async {
    if (_estimating || _query.length < 2) return;
    setState(() => _estimating = true);
    final food = await ref.read(foodSearchApiProvider).estimate(_query);
    if (!mounted) return;
    setState(() => _estimating = false);
    if (food == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Couldn\'t estimate "$_query". Try the camera scan.')));
      return;
    }
    _openPortionSheet(food);
  }

  /// Show the AI-estimate footer when the user has a real query and we're
  /// online — the database hits might not be the dish they mean.
  bool get _showEstimateFooter => _query.length >= 2 && !_offline;

  /// Offered when the database results may not be the dish the user means.
  Widget _estimateCta() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      child: ListTile(
        leading: _estimating
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.auto_awesome),
        title: Text(_estimating ? 'Estimating…' : 'Estimate "$_query" with AI'),
        subtitle: const Text('For local dishes no food database has'),
        onTap: _estimating ? null : _estimateWithAi,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add food')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Search any food — "kit kat", "char kway teow"…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                        },
                      ),
              ),
            ),
          ),
          if (_offline)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Offline — showing built-in foods only. Connect for the full database.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('🔎', style: TextStyle(fontSize: 40)),
                            const SizedBox(height: 8),
                            Text('No matches',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                'Try a different spelling, or estimate it with AI.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            if (_query.length >= 2 && !_offline)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
                                child: _estimateCta(),
                              ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: _results.length + (_showEstimateFooter ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i == _results.length) return _estimateCta();
                          final food = _results[i];
                          final detail = food.brand != null && food.brand!.isNotEmpty
                              ? food.brand!
                              : (food.region ?? '');
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Text(food.emoji,
                                  style: const TextStyle(fontSize: 24)),
                              title: Text(food.name),
                              subtitle: Text(
                                '${food.per100g.forGrams(food.defaultGrams).kcal.round()} kcal · ${food.defaultPortionLabel}'
                                '${detail.isNotEmpty ? ' · $detail' : ''}',
                              ),
                              trailing: const Icon(Icons.add_circle_outline),
                              onTap: () => _openPortionSheet(food),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPortionSheet(Food food) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _LogFoodSheet(
        food: food,
        initialMeal: widget.initialMeal,
        onLogged: (meal) {
          Navigator.pop(sheetContext);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${food.name} logged to ${meal.label} ✅')),
          );
        },
      ),
    );
  }
}

class _LogFoodSheet extends ConsumerStatefulWidget {
  const _LogFoodSheet({
    required this.food,
    required this.onLogged,
    this.initialMeal,
  });

  final Food food;
  final String? initialMeal;
  final void Function(Meal meal) onLogged;

  @override
  ConsumerState<_LogFoodSheet> createState() => _LogFoodSheetState();
}

class _LogFoodSheetState extends ConsumerState<_LogFoodSheet> {
  static const _uuid = Uuid();

  late int _portionIndex = 0;
  late double _multiplier = 1.0;
  late Meal _meal = switch (widget.initialMeal) {
    'breakfast' => Meal.breakfast,
    'lunch' => Meal.lunch,
    'dinner' => Meal.dinner,
    'snack' => Meal.snack,
    _ => _mealForNow(),
  };

  static Meal _mealForNow() {
    final hour = DateTime.now().hour;
    if (hour < 11) return Meal.breakfast;
    if (hour < 15) return Meal.lunch;
    if (hour < 21) return Meal.dinner;
    return Meal.snack;
  }

  double get _grams {
    final base = widget.food.portions.isEmpty
        ? 100.0
        : widget.food.portions[_portionIndex].grams;
    return base * _multiplier;
  }

  Future<void> _log() async {
    final now = DateTime.now();
    final dateKey = dateKeyOf(now);
    final portionLabel = widget.food.portions.isEmpty
        ? '${_grams.round()} g'
        : '${_multiplier == 1.0 ? '' : '${_fmtMultiplier(_multiplier)} × '}${widget.food.portions[_portionIndex].label}';

    final entry = DiaryEntry(
      id: _uuid.v4(),
      dateKey: dateKey,
      meal: _meal,
      foodName: widget.food.name,
      grams: _grams,
      nutrition: widget.food.per100g.forGrams(_grams),
      source: EntrySource.search,
      loggedAt: now,
      emoji: widget.food.emoji,
      portionLabel: portionLabel,
      hydrationMl: _grams * (widget.food.hydrationFactor ?? 0),
    );

    await ref.read(diaryProvider(dateKey).notifier).add(entry);
    widget.onLogged(_meal);
  }

  static String _fmtMultiplier(double m) =>
      m == m.roundToDouble() ? '${m.round()}' : m.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nutrition = widget.food.per100g.forGrams(_grams);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            24, 0, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(widget.food.emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(widget.food.name,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (widget.food.portions.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                children: List.generate(widget.food.portions.length, (i) {
                  final p = widget.food.portions[i];
                  return ChoiceChip(
                    label: Text(p.label),
                    selected: _portionIndex == i,
                    onSelected: (_) => setState(() => _portionIndex = i),
                  );
                }),
              ),
              const SizedBox(height: 12),
            ],

            Row(
              children: [
                Text('Amount', style: theme.textTheme.titleSmall),
                Expanded(
                  child: Slider(
                    value: _multiplier,
                    min: 0.25,
                    max: 3.0,
                    divisions: 11,
                    label: '${_fmtMultiplier(_multiplier)}×',
                    onChanged: (v) => setState(() => _multiplier = v),
                  ),
                ),
                Text('${_grams.round()} g',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),

            Center(
              child: Text(
                '${nutrition.kcal.round()} kcal · P ${nutrition.proteinG.round()} · C ${nutrition.carbsG.round()} · F ${nutrition.fatG.round()} g',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 16),

            SegmentedButton<Meal>(
              segments: Meal.values
                  .map((m) =>
                      ButtonSegment(value: m, label: Text(m.emoji)))
                  .toList(),
              selected: {_meal},
              onSelectionChanged: (s) => setState(() => _meal = s.first),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _log,
                icon: const Icon(Icons.check_rounded),
                label: Text('Log to ${_meal.label}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
