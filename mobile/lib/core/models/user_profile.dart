import 'dart:math' as math;

enum Sex { male, female }

enum ActivityLevel { sedentary, light, moderate, active, veryActive }

extension ActivityLabel on ActivityLevel {
  String get label => switch (this) {
        ActivityLevel.sedentary => 'Sedentary',
        ActivityLevel.light => 'Lightly active',
        ActivityLevel.moderate => 'Moderately active',
        ActivityLevel.active => 'Active',
        ActivityLevel.veryActive => 'Very active',
      };

  String get description => switch (this) {
        ActivityLevel.sedentary => 'Desk job, little exercise',
        ActivityLevel.light => 'Exercise 1–3 days/week',
        ActivityLevel.moderate => 'Exercise 3–5 days/week',
        ActivityLevel.active => 'Exercise 6–7 days/week',
        ActivityLevel.veryActive => 'Hard training or physical job',
      };

  double get factor => switch (this) {
        ActivityLevel.sedentary => 1.2,
        ActivityLevel.light => 1.375,
        ActivityLevel.moderate => 1.55,
        ActivityLevel.active => 1.725,
        ActivityLevel.veryActive => 1.9,
      };
}

enum Goal { lose, maintain, gain }

extension GoalLabel on Goal {
  String get label => switch (this) {
        Goal.lose => 'Lose weight',
        Goal.maintain => 'Maintain',
        Goal.gain => 'Build muscle',
      };

  /// Daily kcal adjustment vs TDEE. Moderate, sustainable defaults.
  double get kcalDelta => switch (this) {
        Goal.lose => -450,
        Goal.maintain => 0,
        Goal.gain => 300,
      };
}

class UserProfile {
  const UserProfile({
    required this.name,
    required this.sex,
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.activity,
    required this.goal,
  });

  final String name;
  final Sex sex;
  final int age;
  final double heightCm;
  final double weightKg;
  final ActivityLevel activity;
  final Goal goal;

  /// Mifflin-St Jeor.
  double get bmr {
    final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
    return sex == Sex.male ? base + 5 : base - 161;
  }

  double get tdee => bmr * activity.factor;

  /// Daily target with the ED safeguard from the PRD: never below BMR × 0.85,
  /// regardless of goal settings.
  double get kcalTarget => math.max(tdee + goal.kcalDelta, bmr * 0.85);

  /// Protein 1.6 g/kg (capped at 35% of kcal), fat 30% of kcal, carbs remainder.
  double get proteinTargetG =>
      math.min(1.6 * weightKg, kcalTarget * 0.35 / 4);

  double get fatTargetG => kcalTarget * 0.30 / 9;

  double get carbsTargetG =>
      (kcalTarget - proteinTargetG * 4 - fatTargetG * 9) / 4;

  /// 33 ml/kg, clamped to a sensible 1.5–4 L band — heavier bodies don't
  /// need unbounded water and light bodies still need a floor.
  double get waterTargetMl => (weightKg * 33).clamp(1500.0, 4000.0);

  UserProfile copyWith({
    String? name,
    Sex? sex,
    int? age,
    double? heightCm,
    double? weightKg,
    ActivityLevel? activity,
    Goal? goal,
  }) =>
      UserProfile(
        name: name ?? this.name,
        sex: sex ?? this.sex,
        age: age ?? this.age,
        heightCm: heightCm ?? this.heightCm,
        weightKg: weightKg ?? this.weightKg,
        activity: activity ?? this.activity,
        goal: goal ?? this.goal,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'sex': sex.name,
        'age': age,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'activity': activity.name,
        'goal': goal.name,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        name: json['name'] as String,
        sex: Sex.values.byName(json['sex'] as String),
        age: json['age'] as int,
        heightCm: (json['height_cm'] as num).toDouble(),
        weightKg: (json['weight_kg'] as num).toDouble(),
        activity: ActivityLevel.values.byName(json['activity'] as String),
        goal: Goal.values.byName(json['goal'] as String),
      );
}
