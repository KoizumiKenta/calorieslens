<?php

namespace App\Services\Ai;

/**
 * Conversational nutrition coach. Stateless: the app sends the user's message,
 * a compact context block (today's numbers, targets, goal) and recent turns;
 * Gemini replies grounded in those numbers. Returns ['reply' => string] or
 * ['error' => ...]. The phone keeps an on-device rule-based fallback for when
 * this is unreachable.
 */
class CoachService
{
    public function __construct(private readonly GeminiClient $gemini) {}

    /**
     * @param  array<int,array{role:string,text:string}>  $history  prior turns, oldest first
     * @return array<string,mixed>  ['reply' => string] | ['error' => ..., 'message' => ...]
     */
    public function reply(string $message, string $context, array $history = []): array
    {
        $contents = [];
        foreach ($history as $turn) {
            $role = ($turn['role'] ?? 'user') === 'coach' ? 'model' : 'user';
            $text = trim((string) ($turn['text'] ?? ''));
            if ($text !== '') {
                $contents[] = ['role' => $role, 'parts' => [['text' => $text]]];
            }
        }
        $contents[] = ['role' => 'user', 'parts' => [['text' => $message]]];

        $payload = [
            'systemInstruction' => ['parts' => [['text' => $this->prompt($context)]]],
            'contents' => $contents,
            'generationConfig' => [
                'responseMimeType' => 'application/json',
                'responseSchema' => GeminiClient::toGeminiSchema([
                    'type' => 'object',
                    'properties' => ['reply' => ['type' => 'string']],
                    'required' => ['reply'],
                ]),
                'maxOutputTokens' => 1024,
                'temperature' => 0.6,
            ],
        ];

        $raw = $this->gemini->generate($payload, [config('calorielens.text_model')]);
        if (isset($raw['error'])) {
            return $raw;
        }

        $reply = trim((string) ($raw['reply'] ?? ''));
        if ($reply === '') {
            return ['error' => 'empty_reply', 'message' => 'Coach returned no answer.'];
        }

        return ['reply' => $reply];
    }

    private function prompt(string $context): string
    {
        return <<<PROMPT
You are the in-app nutrition coach for CalorieLens, a calorie-tracking app used mainly in Malaysia and Southeast Asia.

Your job: give short, practical, encouraging nutrition and food guidance grounded in the user's REAL numbers below. Talk like a friendly knowledgeable coach, not a textbook.

Rules:
- Keep replies to 2-4 sentences. No headings, no bullet lists unless the user explicitly asks for a list.
- Always use the user's actual numbers from the context when relevant (calories left, protein gap, water, weight trend). Do not invent numbers that aren't given.
- Know local food: nasi lemak, char kuey teow, roti canai, teh tarik, chicken rice, laksa, yong tau foo, etc. Give realistic kcal ballparks and lighter swaps.
- Be supportive and non-judgmental. Encourage steady, sustainable habits.
- You may answer general nutrition questions (protein, fibre, hydration, eating out, portion sizes, meal timing) even when not in the context.
- If asked for medical diagnosis, prescription advice, or anything about extreme/very-low-calorie dieting, decline gently and suggest a doctor or dietitian. Never give advice that promotes disordered eating.
- If the user asks something completely unrelated to food, health, or their tracking, briefly steer back to what you can help with.

User's current context:
{$context}
PROMPT;
    }
}
