<?php

declare(strict_types=1);

namespace App\Domain\AI\Exceptions;

use RuntimeException;

class AllProvidersFailedException extends RuntimeException
{
    /** @param array<string, string> $providerErrors */
    public function __construct(
        public readonly string $capability,
        public readonly array $providerErrors,
    ) {
        parent::__construct(sprintf(
            'All %s providers failed: %s',
            $capability,
            json_encode($providerErrors),
        ));
    }
}
