<?php

namespace Starter\ServerDocumentation\Providers;

use App\Filament\Admin\Resources\Servers\ServerResource;
use App\Models\Server;
use App\Models\User;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\ServiceProvider;
use Starter\ServerDocumentation\Filament\Admin\RelationManagers\DocumentsRelationManager;
use Starter\ServerDocumentation\Models\Document;
use Starter\ServerDocumentation\Policies\DocumentPolicy;

class ServerDocumentationServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        // No external dependencies - uses Pelican's bundled packages
    }

    public function boot(): void
    {
        // Register policy
        Gate::policy(Document::class, DocumentPolicy::class);

        // Register document permissions as Gates
        // These control admin panel access to document management
        // Root admins always have access; can be extended for role-based access
        $this->registerDocumentPermissions();

        // Load migrations
        $this->loadMigrationsFrom(
            plugin_path('server-documentation', 'database/migrations')
        );

        // Load views
        $this->loadViewsFrom(
            plugin_path('server-documentation', 'resources/views'),
            'server-documentation'
        );

        // Load translations
        $this->loadTranslationsFrom(
            plugin_path('server-documentation', 'lang'),
            'server-documentation'
        );

        // Register Server -> documents relationship dynamically
        Server::resolveRelationUsing('documents', function (Server $server) {
            return $server->belongsToMany(
                Document::class,
                'document_server',
                'server_id',
                'document_id'
            )->withPivot('sort_order')->withTimestamps()->orderByPivot('sort_order');
        });

        // Register DocumentsRelationManager on ServerResource
        ServerResource::registerCustomRelations(DocumentsRelationManager::class);
    }

    /**
     * Register document-related Gates for admin panel permissions.
     *
     * These gates control who can manage documents in the admin panel.
     * Access is granted to:
     * - Root Admins (full access)
     * - Server Admins (users with server update/create permissions)
     */
    protected function registerDocumentPermissions(): void
    {
        $permissions = [
            'viewList document',
            'view document',
            'create document',
            'update document',
            'delete document',
        ];

        foreach ($permissions as $permission) {
            Gate::define($permission, function (User $user) {
                // Root admins always have full document access
                if ($user->isRootAdmin()) {
                    return true;
                }

                // Server Admins (users with server management permissions) can manage documents
                return $user->can('update server') || $user->can('create server');
            });
        }
    }
}
