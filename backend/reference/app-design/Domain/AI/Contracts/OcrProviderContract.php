<?php

declare(strict_types=1);

namespace App\Domain\AI\Contracts;

use App\Domain\AI\DTO\OcrResult;

interface OcrProviderContract
{
    public function name(): string;

    /**
     * Extract text + word geometry from an image (label, receipt, menu).
     * Geometry is required: the LabelParser disambiguates per-100g vs
     * per-serving columns spatially.
     *
     * @param  string  $imageBytes  Pre-processed (deskewed) image
     *
     * @throws \App\Domain\AI\Exceptions\ProviderException
     */
    public function extract(string $imageBytes, string $mime, array $languageHints = []): OcrResult;
}
