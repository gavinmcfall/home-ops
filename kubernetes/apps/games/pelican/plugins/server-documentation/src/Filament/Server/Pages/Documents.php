<?php

namespace Starter\ServerDocumentation\Filament\Server\Pages;

use App\Models\Server;
use Filament\Facades\Filament;
use Filament\Pages\Page;
use Illuminate\Support\Collection;
use Starter\ServerDocumentation\Models\Document;

class Documents extends Page
{
    protected static ?int $navigationSort = 50;

    protected static string|\BackedEnum|null $navigationIcon = 'tabler-file-text';

    protected string $view = 'server-documentation::filament.server.pages.documents';

    public ?Document $selectedDocument = null;

    public static function getNavigationLabel(): string
    {
        return 'Documents';
    }

    public function getTitle(): string
    {
        return 'Server Documents';
    }

    public static function canAccess(): bool
    {
        /** @var Server $server */
        $server = Filament::getTenant();

        if (!$server) {
            return false;
        }

        // Check if there are any documents for this server
        return static::getDocumentsForServer($server)->isNotEmpty();
    }

    public function mount(): void
    {
        $documents = $this->getDocuments();

        // Auto-select first document if available
        if ($documents->isNotEmpty() && !$this->selectedDocument) {
            $this->selectedDocument = $documents->first();
        }
    }

    public function selectDocument(int $documentId): void
    {
        $this->selectedDocument = $this->getDocuments()->firstWhere('id', $documentId);
    }

    public function getDocuments(): Collection
    {
        /** @var Server $server */
        $server = Filament::getTenant();

        return static::getDocumentsForServer($server);
    }

    protected static function getDocumentsForServer(Server $server): Collection
    {
        $user = user();
        $canViewAdminDocs = $user?->can('update server', $server);

        // Get documents directly attached to this server
        $attachedDocs = $server->documents()
            ->where('is_published', true)
            ->when(!$canViewAdminDocs, fn ($q) => $q->where('type', 'player'))
            ->orderByPivot('sort_order')
            ->get();

        // Get global documents
        $globalDocs = Document::query()
            ->where('is_global', true)
            ->where('is_published', true)
            ->when(!$canViewAdminDocs, fn ($q) => $q->where('type', 'player'))
            ->orderBy('sort_order')
            ->get();

        // Merge and deduplicate (attached docs take priority)
        $attachedIds = $attachedDocs->pluck('id')->toArray();
        $globalDocs = $globalDocs->filter(fn ($doc) => !in_array($doc->id, $attachedIds));

        return $attachedDocs->concat($globalDocs);
    }
}
