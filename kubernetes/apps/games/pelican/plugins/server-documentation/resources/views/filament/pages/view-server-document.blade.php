<x-filament-panels::page>
    <div class="space-y-6">
        {{-- Document Header --}}
        <div class="flex items-center justify-between">
            <div>
                <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
                    {{ $document->title }}
                </h1>
                <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                    Last updated {{ $document->updated_at->diffForHumans() }}
                    @if($document->lastEditor)
                        by {{ $document->lastEditor->username }}
                    @endif
                </p>
            </div>

            @if($document->type === 'admin')
                <x-filament::badge color="danger">
                    Admin Document
                </x-filament::badge>
            @endif
        </div>

        {{-- Document Content --}}
        <x-filament::section>
            <div class="prose prose-sm dark:prose-invert max-w-none">
                {!! $content !!}
            </div>
        </x-filament::section>

        {{-- Back Link --}}
        <div class="flex justify-start">
            <x-filament::link
                :href="\Starter\ServerDocumentation\Filament\Server\Pages\ListServerDocuments::getUrl()"
                icon="tabler-arrow-left"
            >
                Back to Documents
            </x-filament::link>
        </div>
    </div>
</x-filament-panels::page>
