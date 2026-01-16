<?php

namespace Starter\ServerDocumentation\Policies;

use App\Models\Server;
use App\Models\User;
use Starter\ServerDocumentation\Models\Document;

class DocumentPolicy
{
    /**
     * Admin panel: Can user view documents list?
     */
    public function viewAny(User $user): bool
    {
        return $user->can('document.view');
    }

    /**
     * Admin panel: Can user view a specific document?
     */
    public function view(User $user, Document $document): bool
    {
        return $user->can('document.view');
    }

    /**
     * Admin panel: Can user create documents?
     */
    public function create(User $user): bool
    {
        return $user->can('document.create');
    }

    /**
     * Admin panel: Can user update documents?
     */
    public function update(User $user, Document $document): bool
    {
        return $user->can('document.update');
    }

    /**
     * Admin panel: Can user delete documents?
     */
    public function delete(User $user, Document $document): bool
    {
        return $user->can('document.delete');
    }

    /**
     * Admin panel: Can user restore soft-deleted documents?
     */
    public function restore(User $user, Document $document): bool
    {
        return $user->can('document.delete');
    }

    /**
     * Admin panel: Can user permanently delete documents?
     */
    public function forceDelete(User $user, Document $document): bool
    {
        return $user->can('document.delete');
    }

    /**
     * Server panel: Can user view this document on a specific server?
     * This is the main permission check for the player/user view.
     */
    public function viewOnServer(User $user, Document $document, Server $server): bool
    {
        // Document must be published
        if (!$document->is_published) {
            return false;
        }

        // Document must be linked to server or be global
        if (!$document->is_global &&
            !$document->servers()->where('servers.id', $server->id)->exists()) {
            return false;
        }

        // Admin docs require Server.Update permission
        if ($document->type === 'admin') {
            return $user->can('update', $server);
        }

        // Player docs require Server.View permission
        return $user->can('view', $server);
    }
}
