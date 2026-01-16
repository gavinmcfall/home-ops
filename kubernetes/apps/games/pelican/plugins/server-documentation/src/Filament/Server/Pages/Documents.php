<?php

namespace Starter\ServerDocumentation\Filament\Server\Pages;

use App\Enums\SubuserPermission;
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

    /**
     * Get the user's document access tier.
     * Returns an array of document types the user can view.
     *
     * Hierarchy (highest to lowest):
     * - host_admin: Root Admin only
     * - server_admin: Server owner OR admins with update/create server permission
     * - server_mod: Subusers with any control.* permission
     * - player: Everyone with server access
     */
    protected static function getAllowedDocTypes(Server $server): array
    {
        $user = user();

        if (!$user) {
            return ['player'];
        }

        // Host Admin: Root Admin only
        if ($user->isRootAdmin()) {
            // Include 'admin' for backwards compatibility with old docs
            return ['host_admin', 'server_admin', 'admin', 'server_mod', 'player'];
        }

        // Server Admin: Server owner OR has update/create server admin permission
        $isServerAdmin = $server->owner_id === $user->id ||
            $user->hasPermissionTo('update server') ||
            $user->hasPermissionTo('create server');

        if ($isServerAdmin) {
            // Include 'admin' for backwards compatibility with old docs
            return ['server_admin', 'admin', 'server_mod', 'player'];
        }

        // Server Mod: Has any control.* subuser permission on this server
        $isServerMod = $user->can(SubuserPermission::ControlConsole, $server) ||
            $user->can(SubuserPermission::ControlStart, $server) ||
            $user->can(SubuserPermission::ControlStop, $server) ||
            $user->can(SubuserPermission::ControlRestart, $server);

        if ($isServerMod) {
            return ['server_mod', 'player'];
        }

        // Player: Default - can only see player docs
        return ['player'];
    }

    protected static function getDocumentsForServer(Server $server): Collection
    {
        $allowedTypes = static::getAllowedDocTypes($server);

        // Get documents directly attached to this server
        $attachedDocs = $server->documents()
            ->where('is_published', true)
            ->whereIn('type', $allowedTypes)
            ->orderByPivot('sort_order')
            ->get();

        // Get global documents
        $globalDocs = Document::query()
            ->where('is_global', true)
            ->where('is_published', true)
            ->whereIn('type', $allowedTypes)
            ->orderBy('sort_order')
            ->get();

        // Merge and deduplicate (attached docs take priority)
        $attachedIds = $attachedDocs->pluck('id')->toArray();
        $globalDocs = $globalDocs->filter(fn ($doc) => !in_array($doc->id, $attachedIds));

        return $attachedDocs->concat($globalDocs);
    }
}
