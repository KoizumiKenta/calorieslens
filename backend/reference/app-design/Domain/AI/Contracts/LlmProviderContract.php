<?php

declare(strict_types=1);

namespace App\Domain\AI\Contracts;

interface LlmProviderContract
{
    public function name(): string;

    /**
     * Single-shot structured completion (voice-log structuring, label repair,
     * plan generation). $schema is a JSON Schema the output must satisfy.
     *
     * @return array Parsed, schema-validated JSON
     *
     * @throws \App\Domain\AI\Exceptions\ProviderException
     */
    public function complete(string $system, array $messages, ?array $schema = null, ?string $model = null): array;

    /**
     * Streaming chat for the coach. $tools follow the internal tool spec
     * (Domain\Coaching\Tools); yields text deltas, returns the final message.
     *
     * @param  callable(string): void  $onDelta
     */
    public function stream(string $system, array $messages, array $tools, callable $onDelta): array;
}
