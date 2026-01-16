<x-filament-panels::page>
    @php
        $documents = $this->getDocuments();
    @endphp

    @if($documents->isEmpty())
        <div class="flex flex-col items-center justify-center p-8 text-center">
            <x-filament::icon
                icon="tabler-file-off"
                class="h-12 w-12 text-gray-400 dark:text-gray-500 mb-4"
            />
            <h3 class="text-lg font-medium text-gray-900 dark:text-white">
                No documents available
            </h3>
            <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                There are no documents for this server yet.
            </p>
        </div>
    @else
        <div class="grid grid-cols-1 lg:grid-cols-4 gap-6">
            {{-- Document list sidebar --}}
            <div class="lg:col-span-1">
                <div class="bg-white dark:bg-gray-900 rounded-xl shadow-sm ring-1 ring-gray-950/5 dark:ring-white/10">
                    <div class="p-4 border-b border-gray-200 dark:border-gray-700">
                        <h3 class="text-sm font-medium text-gray-900 dark:text-white">Documents</h3>
                    </div>
                    <nav class="p-2 space-y-1">
                        @foreach($documents as $document)
                            <button
                                wire:click="selectDocument({{ $document->id }})"
                                @class([
                                    'w-full text-left px-3 py-2 rounded-lg text-sm transition-colors',
                                    'bg-primary-50 text-primary-700 dark:bg-primary-900/50 dark:text-primary-400' => $selectedDocument?->id === $document->id,
                                    'text-gray-700 hover:bg-gray-50 dark:text-gray-300 dark:hover:bg-gray-800' => $selectedDocument?->id !== $document->id,
                                ])
                            >
                                <div class="flex items-center gap-2">
                                    @if($document->type === 'admin')
                                        <x-filament::icon
                                            icon="tabler-lock"
                                            class="h-4 w-4 text-danger-500"
                                        />
                                    @else
                                        <x-filament::icon
                                            icon="tabler-file-text"
                                            class="h-4 w-4"
                                        />
                                    @endif
                                    <span class="truncate">{{ $document->title }}</span>
                                </div>
                                @if($document->is_global)
                                    <span class="text-xs text-gray-500 dark:text-gray-400 ml-6">Global</span>
                                @endif
                            </button>
                        @endforeach
                    </nav>
                </div>
            </div>

            {{-- Document content --}}
            <div class="lg:col-span-3">
                @if($selectedDocument)
                    <div class="bg-white dark:bg-gray-900 rounded-xl shadow-sm ring-1 ring-gray-950/5 dark:ring-white/10">
                        <div class="p-4 border-b border-gray-200 dark:border-gray-700">
                            <div class="flex items-center justify-between">
                                <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
                                    {{ $selectedDocument->title }}
                                </h2>
                                <div class="flex items-center gap-2">
                                    @if($selectedDocument->type === 'admin')
                                        <span class="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium rounded-full bg-danger-50 text-danger-700 dark:bg-danger-900/50 dark:text-danger-400">
                                            <x-filament::icon icon="tabler-lock" class="h-3 w-3" />
                                            Admin Only
                                        </span>
                                    @endif
                                    @if($selectedDocument->is_global)
                                        <span class="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium rounded-full bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300">
                                            <x-filament::icon icon="tabler-world" class="h-3 w-3" />
                                            Global
                                        </span>
                                    @endif
                                </div>
                            </div>
                            @if($selectedDocument->updated_at)
                                <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                                    Last updated {{ $selectedDocument->updated_at->diffForHumans() }}
                                </p>
                            @endif
                        </div>
                        <div class="p-6 prose prose-sm dark:prose-invert max-w-none">
                            {!! $selectedDocument->content !!}
                        </div>
                    </div>
                @else
                    <div class="flex flex-col items-center justify-center p-8 text-center bg-white dark:bg-gray-900 rounded-xl shadow-sm ring-1 ring-gray-950/5 dark:ring-white/10">
                        <x-filament::icon
                            icon="tabler-file-text"
                            class="h-12 w-12 text-gray-400 dark:text-gray-500 mb-4"
                        />
                        <h3 class="text-lg font-medium text-gray-900 dark:text-white">
                            Select a document
                        </h3>
                        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                            Choose a document from the list to view its contents.
                        </p>
                    </div>
                @endif
            </div>
        </div>
    @endif
</x-filament-panels::page>
