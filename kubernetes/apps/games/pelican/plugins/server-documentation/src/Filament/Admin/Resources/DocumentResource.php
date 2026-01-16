<?php

namespace Starter\ServerDocumentation\Filament\Admin\Resources;

use Filament\Actions\DeleteBulkAction;
use Filament\Actions\EditAction;
use Filament\Forms\Components\Placeholder;
use Filament\Forms\Components\RichEditor;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Forms\Components\Toggle;
use Filament\Resources\Pages\PageRegistration;
use Filament\Resources\Resource;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Schema;
use Illuminate\Support\HtmlString;
use Filament\Tables\Columns\IconColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Filters\TernaryFilter;
use Filament\Tables\Filters\TrashedFilter;
use Filament\Tables\Table;
use Illuminate\Support\Str;
use Starter\ServerDocumentation\Filament\Admin\Resources\DocumentResource\Pages;
use Starter\ServerDocumentation\Filament\Admin\Resources\DocumentResource\RelationManagers;
use Starter\ServerDocumentation\Models\Document;

class DocumentResource extends Resource
{
    protected static ?string $model = Document::class;

    protected static string|\BackedEnum|null $navigationIcon = 'tabler-file-text';

    protected static ?int $navigationSort = 10;

    protected static ?string $recordTitleAttribute = 'title';

    /**
     * Allow access to anyone who can access the admin panel.
     * Document visibility is controlled by type, not by admin permissions.
     */
    public static function canAccess(): bool
    {
        return true;
    }

    public static function getNavigationLabel(): string
    {
        return 'Documents';
    }

    public static function getModelLabel(): string
    {
        return 'Document';
    }

    public static function getPluralModelLabel(): string
    {
        return 'Documents';
    }

    public static function getNavigationGroup(): ?string
    {
        return null;
    }

    public static function getNavigationBadge(): ?string
    {
        return (string) static::getEloquentQuery()->count() ?: null;
    }

    public static function form(Schema $schema): Schema
    {
        return static::defaultForm($schema);
    }

    public static function defaultForm(Schema $schema): Schema
    {
        return $schema
            ->columns(1)
            ->components([
                Section::make('Document Details')->schema([
                    TextInput::make('title')
                        ->required()
                        ->maxLength(255)
                        ->live(onBlur: true)
                        ->afterStateUpdated(fn ($state, $set, ?Document $record) =>
                            $record === null ? $set('slug', Str::slug($state)) : null
                        ),

                    TextInput::make('slug')
                        ->required()
                        ->maxLength(255)
                        ->unique(ignoreRecord: true)
                        ->rules(['alpha_dash']),

                    Select::make('type')
                        ->options([
                            'host_admin' => 'Host Admin (Root Admins only)',
                            'server_admin' => 'Server Admin (Server owners + admins with Server Update/Create)',
                            'server_mod' => 'Server Mod (Subusers with control permissions)',
                            'player' => 'Player (Anyone with server access)',
                        ])
                        ->default('player')
                        ->required()
                        ->native(false),

                    Toggle::make('is_global')
                        ->label('All Servers')
                        ->helperText('Show on all servers (otherwise attach to specific servers below)'),

                    Toggle::make('is_published')
                        ->default(true)
                        ->helperText('Unpublished documents are only visible to admins'),

                    TextInput::make('sort_order')
                        ->numeric()
                        ->default(0)
                        ->helperText('Lower numbers appear first'),
                ])->columns(3)->columnSpanFull(),

                Section::make('Content')->schema([
                    RichEditor::make('content')
                        ->required()
                        ->extraAttributes(['style' => 'min-height: 400px;'])
                        ->columnSpanFull(),
                ])->columnSpanFull(),

                Section::make('Permission Guide')
                    ->description('Understanding document visibility')
                    ->collapsed()
                    ->schema([
                        Placeholder::make('help')
                            ->label('')
                            ->content(new HtmlString('
                                <div class="prose prose-sm dark:prose-invert max-w-none">
                                    <p class="text-sm text-gray-500 dark:text-gray-400 mb-4">
                                        <strong>Type</strong> controls <em>who</em> can see the document.
                                        <strong>All Servers</strong> controls <em>where</em> it appears.
                                    </p>

                                    <table class="min-w-full text-sm">
                                        <thead>
                                            <tr class="border-b border-gray-200 dark:border-gray-700">
                                                <th class="text-left py-2 pr-4 font-medium">Type</th>
                                                <th class="text-left py-2 pr-4 font-medium">Who Can See</th>
                                            </tr>
                                        </thead>
                                        <tbody class="divide-y divide-gray-100 dark:divide-gray-800">
                                            <tr>
                                                <td class="py-2 pr-4"><span class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-md bg-danger-50 text-danger-700 dark:bg-danger-900/50 dark:text-danger-400">Host Admin</span></td>
                                                <td class="py-2 text-gray-600 dark:text-gray-300">Root Admins only</td>
                                            </tr>
                                            <tr>
                                                <td class="py-2 pr-4"><span class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-md bg-warning-50 text-warning-700 dark:bg-warning-900/50 dark:text-warning-400">Server Admin</span></td>
                                                <td class="py-2 text-gray-600 dark:text-gray-300">Server owners + admins with Server Update/Create permission</td>
                                            </tr>
                                            <tr>
                                                <td class="py-2 pr-4"><span class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-md bg-info-50 text-info-700 dark:bg-info-900/50 dark:text-info-400">Server Mod</span></td>
                                                <td class="py-2 text-gray-600 dark:text-gray-300">Subusers with control permissions (start/stop/restart)</td>
                                            </tr>
                                            <tr>
                                                <td class="py-2 pr-4"><span class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-md bg-success-50 text-success-700 dark:bg-success-900/50 dark:text-success-400">Player</span></td>
                                                <td class="py-2 text-gray-600 dark:text-gray-300">Anyone with server access</td>
                                            </tr>
                                        </tbody>
                                    </table>

                                    <p class="text-sm text-gray-500 dark:text-gray-400 mt-4 mb-2"><strong>Examples:</strong></p>
                                    <ul class="text-sm text-gray-600 dark:text-gray-300 space-y-1 list-disc list-inside">
                                        <li><strong>Player + All Servers</strong> → Welcome guide everyone sees everywhere</li>
                                        <li><strong>Player + Specific Server</strong> → Rules for one server only</li>
                                        <li><strong>Server Admin + All Servers</strong> → Company-wide admin procedures</li>
                                        <li><strong>Server Mod + Specific Server</strong> → Mod notes for one server</li>
                                    </ul>

                                    <p class="text-xs text-gray-400 dark:text-gray-500 mt-4">
                                        Higher tiers can see all docs at their level and below (e.g., Server Admin sees Server Admin, Server Mod, and Player docs).
                                    </p>
                                </div>
                            ')),
                    ])->columnSpanFull(),
            ]);
    }

    public static function table(Table $table): Table
    {
        return static::defaultTable($table);
    }

    public static function defaultTable(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('title')
                    ->searchable()
                    ->sortable()
                    ->description(fn (Document $record) => Str::limit(strip_tags($record->content), 50)),

                TextColumn::make('type')
                    ->badge()
                    ->formatStateUsing(fn (string $state): string => match ($state) {
                        'host_admin' => 'Host Admin',
                        'server_admin', 'admin' => 'Server Admin',
                        'server_mod' => 'Server Mod',
                        'player' => 'Player',
                        default => $state,
                    })
                    ->color(fn (string $state): string => match ($state) {
                        'host_admin' => 'danger',
                        'server_admin', 'admin' => 'warning',
                        'server_mod' => 'info',
                        'player' => 'success',
                        default => 'gray',
                    }),

                IconColumn::make('is_global')
                    ->boolean()
                    ->label('Global')
                    ->trueIcon('tabler-world')
                    ->falseIcon('tabler-world-off'),

                IconColumn::make('is_published')
                    ->boolean()
                    ->label('Published'),

                TextColumn::make('servers_count')
                    ->counts('servers')
                    ->label('Servers')
                    ->badge(),

                TextColumn::make('author.username')
                    ->label('Author')
                    ->toggleable(isToggledHiddenByDefault: true),

                TextColumn::make('updated_at')
                    ->dateTime()
                    ->sortable()
                    ->toggleable(),
            ])
            ->filters([
                SelectFilter::make('type')
                    ->options([
                        'host_admin' => 'Host Admin',
                        'server_admin' => 'Server Admin',
                        'server_mod' => 'Server Mod',
                        'player' => 'Player',
                    ]),

                TernaryFilter::make('is_global')
                    ->label('Global'),

                TernaryFilter::make('is_published')
                    ->label('Published'),

                TrashedFilter::make(),
            ])
            ->recordActions([
                EditAction::make(),
            ])
            ->groupedBulkActions([
                DeleteBulkAction::make(),
            ])
            ->defaultSort('sort_order')
            ->emptyStateIcon('tabler-file-off')
            ->emptyStateHeading('No documents yet')
            ->emptyStateDescription('Create your first document to get started.');
    }

    /** @return class-string[] */
    public static function getRelations(): array
    {
        return [
            RelationManagers\ServersRelationManager::class,
        ];
    }

    /** @return array<string, PageRegistration> */
    public static function getPages(): array
    {
        return [
            'index' => Pages\ListDocuments::route('/'),
            'create' => Pages\CreateDocument::route('/create'),
            'edit' => Pages\EditDocument::route('/{record}/edit'),
        ];
    }
}
