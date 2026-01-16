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
                        <div class="p-6 document-content">
                            <style>
                                .document-content h1 { font-size: 1.875rem; font-weight: 700; margin-top: 1.5rem; margin-bottom: 1rem; color: rgb(var(--gray-100)); }
                                .document-content h2 { font-size: 1.5rem; font-weight: 600; margin-top: 1.5rem; margin-bottom: 0.75rem; color: rgb(var(--gray-100)); }
                                .document-content h3 { font-size: 1.25rem; font-weight: 600; margin-top: 1.25rem; margin-bottom: 0.5rem; color: rgb(var(--gray-200)); }
                                .document-content h4 { font-size: 1.125rem; font-weight: 600; margin-top: 1rem; margin-bottom: 0.5rem; color: rgb(var(--gray-200)); }
                                .document-content p { margin-top: 0.75rem; margin-bottom: 0.75rem; color: rgb(var(--gray-300)); line-height: 1.625; }
                                .document-content ul, .document-content ol { margin-top: 0.75rem; margin-bottom: 0.75rem; padding-left: 1.5rem; color: rgb(var(--gray-300)); }
                                .document-content ul { list-style-type: disc; }
                                .document-content ol { list-style-type: decimal; }
                                .document-content li { margin-top: 0.375rem; margin-bottom: 0.375rem; }
                                .document-content li > ul, .document-content li > ol { margin-top: 0.375rem; margin-bottom: 0.375rem; }
                                .document-content strong { font-weight: 600; color: rgb(var(--gray-100)); }
                                .document-content em { font-style: italic; }
                                .document-content code { background-color: rgb(var(--gray-800)); padding: 0.125rem 0.375rem; border-radius: 0.25rem; font-size: 0.875rem; color: rgb(var(--primary-400)); }
                                .document-content pre { background-color: rgb(var(--gray-800)); padding: 1rem; border-radius: 0.5rem; overflow-x: auto; margin-top: 1rem; margin-bottom: 1rem; }
                                .document-content pre code { background: none; padding: 0; }
                                .document-content a { color: rgb(var(--primary-400)); text-decoration: underline; }
                                .document-content a:hover { color: rgb(var(--primary-300)); }
                                .document-content blockquote { border-left: 4px solid rgb(var(--gray-600)); padding-left: 1rem; margin: 1rem 0; color: rgb(var(--gray-400)); font-style: italic; }
                                .document-content hr { border-color: rgb(var(--gray-700)); margin: 1.5rem 0; }
                                .document-content table { width: 100%; border-collapse: collapse; margin: 1rem 0; }
                                .document-content th, .document-content td { border: 1px solid rgb(var(--gray-700)); padding: 0.5rem 0.75rem; text-align: left; }
                                .document-content th { background-color: rgb(var(--gray-800)); font-weight: 600; color: rgb(var(--gray-100)); }
                                .document-content td { color: rgb(var(--gray-300)); }
                                .document-content > *:first-child { margin-top: 0; }
                            </style>
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
