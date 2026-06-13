<?php

declare(strict_types=1);

namespace App\Domain\AI\Exceptions;

use RuntimeException;

class ProviderException extends RuntimeException
{
    public function __construct(
        public readonly string $provider,
        string $message,
        public readonly bool $retryable = true,
        public readonly ?int $httpStatus = null,
    ) {
        parent::__construct("[{$provider}] {$message}");
    }

    public static function rateLimited(string $provider): self
    {
        return new self($provider, 'Rate limited', retryable: true, httpStatus: 429);
    }

    public static function invalidResponse(string $provider, string $detail): self
    {
        // Schema violations after the repair attempt: fail over, don't retry same provider
        return new self($provider, "Invalid response: {$detail}", retryable: false);
    }
}
