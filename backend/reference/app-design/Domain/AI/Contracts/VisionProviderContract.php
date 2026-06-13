<?php

declare(strict_types=1);

namespace App\Domain\AI\Contracts;

use App\Domain\AI\DTO\VisionAnalysis;
use App\Domain\AI\DTO\VisionRequest;

interface VisionProviderContract
{
    public function name(): string;

    /**
     * Analyze one or more meal images and return structured detections.
     * Implementations MUST return schema-valid VisionAnalysis or throw
     * ProviderException — never partially-parsed prose.
     *
     * @throws \App\Domain\AI\Exceptions\ProviderException
     */
    public function analyze(VisionRequest $request): VisionAnalysis;
}
