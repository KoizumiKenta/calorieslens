<?php

declare(strict_types=1);

namespace App\Domain\AI\Contracts;

interface SpeechProviderContract
{
    public function name(): string;

    /**
     * @param  string  $audioBytes  Opus/AAC ≤ 60 s
     * @param  array<string>  $languageHints  BCP-47, e.g. ['en', 'ms'] for Manglish
     *
     * @throws \App\Domain\AI\Exceptions\ProviderException
     */
    public function transcribe(string $audioBytes, string $mime, array $languageHints = []): string;
}
