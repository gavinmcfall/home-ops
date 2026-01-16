<?php

namespace Starter\ServerDocumentation\Providers;

use App\Filament\Admin\Resources\Servers\ServerResource;
use App\Models\Server;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\ServiceProvider;
use Starter\ServerDocumentation\Filament\Admin\RelationManagers\DocumentsRelationManager;
use Starter\ServerDocumentation\Models\Document;
use Starter\ServerDocumentation\Policies\DocumentPolicy;

class ServerDocumentationServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        //
    }

    public function boot(): void
    {
        // Register policy
        Gate::policy(Document::class, DocumentPolicy::class);

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
}
