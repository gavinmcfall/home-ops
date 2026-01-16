<?php

namespace Starter\ServerDocumentation\Policies;

use App\Enums\SubuserPermission;
use App\Models\Server;
use App\Models\User;
use Starter\ServerDocumentation\Models\Document;

class DocumentPolicy
{
    /**
     * Admin panel: Can user view documents list?
     * Uses Pelican's space-separated permission pattern.
     */
    public function viewAny(User $user): bool
    {
        return $user->can('viewList document');
    }

    /**
     * Admin panel: Can user view a specific document?
     */
    public function view(User $user, Document $document): bool
    {
        return $user->can('view document');
    }

    /**
     * Admin panel: Can user create documents?
     */
    public function create(User $user): bool
    {
        return $user->can('create document');
    }

    /**
     * Admin panel: Can user update documents?
     */
    public function update(User $user, Document $document): bool
    {
        return $user->can('update document');
    }

    /**
     * Admin panel: Can user delete documents?
     */
    public function delete(User $user, Document $document): bool
    {
        return $user->can('delete document');
    }

    /**
     * Admin panel: Can user restore soft-deleted documents?
     */
    public function restore(User $user, Document $document): bool
    {
        return $user->can('delete document');
    }

    /**
     * Admin panel: Can user permanently delete documents?
     */
    public function forceDelete(User $user, Document $document): bool
    {
        return $user->can('delete document');
    }

    /**
     * Server panel: Can user view this document on a specific server?
     * Implements 4-tier permission hierarchy:
     * - host_admin: Root Admin only
     * - server_admin: Server owner OR admin with update/create server permission
     * - server_mod: Subusers with control permissions
     * - player: Anyone with server access
     */
    public function viewOnServer(User $user, Document $document, Server $server): bool
    {
        // Document must be published (unless user is root admin)
        if (!$document->is_published && !$user->isRootAdmin()) {
            return false;
        }

        // Document must be linked to server or be global
        if (!$document->is_global &&
            !$document->servers()->where('servers.id', $server->id)->exists()) {
            return false;
        }

        // Get allowed document types for this user
        $allowedTypes = $this->getAllowedDocTypes($user, $server);

        return in_array($document->type, $allowedTypes);
    }

    /**
     * Get the document types this user can view on this server.
     */
    protected function getAllowedDocTypes(User $user, Server $server): array
    {
        // Host Admin: Root Admin only
        if ($user->isRootAdmin()) {
            return ['host_admin', 'server_admin', 'admin', 'server_mod', 'player'];
        }

        // Server Admin: Server owner OR has update/create server admin permission
        $isServerAdmin = $server->owner_id === $user->id ||
            $user->hasPermissionTo('update server') ||
            $user->hasPermissionTo('create server');

        if ($isServerAdmin) {
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
}
