import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/repositories.dart';
import '../../core/state/providers.dart';

class _Message {
  const _Message(this.text, {required this.fromUser});

  final String text;
  final bool fromUser;
}

/// AI coach chat. v1 answers from on-device rules grounded in the user's
/// real diary numbers, so the conversation is genuinely personal even
/// offline. The backend swap (docs/07-ai-services.md §RAG) replaces
/// _replyTo with the streaming /coach/messages call — same UI.
class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_Message> _messages = [];
  bool _typing = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send([String? quick]) async {
    final text = (quick ?? _controller.text).trim();
    if (text.isEmpty || _typing) return;
    _controller.clear();

    setState(() {
      _messages.add(_Message(text, fromUser: true));
      _typing = true;
    });
    _scrollDown();

    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() {
      _messages.add(_Message(_replyTo(text), fromUser: false));
      _typing = false;
    });
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _replyTo(String text) {
    final profile = ref.read(profileProvider);
    final dateKey = dateKeyOf(DateTime.now());
    final totals = ref.read(dayTotalsProvider(dateKey));
    final water = ref.read(waterProvider(dateKey));
    final q = text.toLowerCase();

    if (profile == null) return 'Finish setting up your profile first and I can give you personal advice.';

    final remaining = profile.kcalTarget - totals.kcal;
    final proteinLeft = profile.proteinTargetG - totals.proteinG;

    if (q.contains('left') || q.contains('remaining') || q.contains('how am i') || q.contains('today')) {
      if (totals.kcal == 0) {
        return 'Nothing logged yet today. Your target is ${profile.kcalTarget.round()} kcal — snap your next meal and I\'ll track it with you.';
      }
      return 'So far today: ${totals.kcal.round()} kcal of ${profile.kcalTarget.round()} '
          '(${remaining >= 0 ? '${remaining.round()} left' : '${(-remaining).round()} over'}). '
          'Protein ${totals.proteinG.round()}/${profile.proteinTargetG.round()} g'
          '${proteinLeft > 15 ? ' — that\'s the gap to focus on. Grilled chicken, eggs, tofu or a shake would close it.' : ' — protein looks solid. 💪'}';
    }
    if (q.contains('dinner') || q.contains('eat tonight') || q.contains('what should i eat')) {
      if (remaining < 300) {
        return 'You have about ${remaining.clamp(0, 9999).round()} kcal left, so keep dinner light: '
            'sup ayam (~250 kcal), a salad with chicken, or yong tau foo soup (pick 6 pieces, skip the fried ones).';
      }
      return 'With ${remaining.round()} kcal left you have room for a proper dinner. '
          'Good fits: chicken rice (~600 kcal, ask for less rice), asam laksa (~440 — one of the lightest hawker bowls), '
          'or grilled fish with 1 bowl of rice (~550). ${proteinLeft > 20 ? 'Prioritise protein — you still need ${proteinLeft.round()} g.' : ''}';
    }
    if (q.contains('nasi lemak')) {
      return 'A standard plate of nasi lemak runs ~620 kcal — the rice and sambal carry most of it. '
          'Make it fit: ask for less rice (−90 kcal), skip the extra sambal spoon (−70), keep the egg and ikan bilis for protein. '
          '${remaining >= 620 ? 'You have room for one today (${remaining.round()} kcal left).' : 'Tight fit today — maybe split the rice or save it for tomorrow.'}';
    }
    if (q.contains('water')) {
      final target = profile.waterTargetMl;
      return 'You\'ve logged ${(water / 1000).toStringAsFixed(2)} L of your ${(target / 1000).toStringAsFixed(1)} L target'
          '${water < target ? ' — about ${((target - water) / 250).ceil()} more glasses to go. 💧' : ' — target hit, nice. 💧'}';
    }
    if (q.contains('protein')) {
      return proteinLeft <= 0
          ? 'Protein target already hit (${totals.proteinG.round()} g) — great day. 💪'
          : 'You need ${proteinLeft.round()} g more protein today. Cheap wins: 2 eggs (13 g), a palm-size chicken breast (35 g), '
              'a block of tauhu (20 g), or a scoop of whey (24 g).';
    }
    if (q.contains('weight') || q.contains('progress')) {
      final logs = ref.read(weightLogProvider);
      if (logs.length < 2) {
        return 'Log your weight a couple of times in Profile and I can talk trends. '
            'Weigh in at the same time each morning for clean data.';
      }
      final delta = logs.last.$2 - logs.first.$2;
      return 'You\'ve gone from ${logs.first.$2.toStringAsFixed(1)} kg to ${logs.last.$2.toStringAsFixed(1)} kg '
          '(${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)} kg). '
          '${profile.goal.name == 'lose' && delta < 0 ? 'Right direction — steady beats fast. 📉' : 'Remember daily fluctuation of ±1 kg is water, not fat. Watch the weekly average.'}';
    }
    return 'I can help with what to eat next, how today is tracking, protein gaps, water, or your weight trend. '
        'Try one of the suggestions below — and once the cloud coach is connected I\'ll handle anything nutrition-related.';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Coach')),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _emptyState(scheme)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_typing ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == _messages.length) {
                        return const Padding(
                          padding: EdgeInsets.all(12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 40,
                              child: LinearProgressIndicator(minHeight: 4),
                            ),
                          ),
                        );
                      }
                      final m = _messages[i];
                      return Align(
                        alignment: m.fromUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.78),
                          decoration: BoxDecoration(
                            color: m.fromUser
                                ? scheme.primary
                                : scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            m.text,
                            style: TextStyle(
                                color: m.fromUser
                                    ? scheme.onPrimary
                                    : scheme.onSurface),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          _quickChips(),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                          hintText: 'Ask your coach…'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🥗', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('Your nutrition coach',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Grounded in your actual diary — ask what to eat next, how today is going, or how to fit in nasi lemak.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickChips() {
    const suggestions = [
      'How am I doing today?',
      'What should I eat for dinner?',
      'Can I fit in nasi lemak?',
      'How much protein do I need?',
    ];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: suggestions
            .map((s) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(s),
                    onPressed: () => _send(s),
                  ),
                ))
            .toList(),
      ),
    );
  }
}
