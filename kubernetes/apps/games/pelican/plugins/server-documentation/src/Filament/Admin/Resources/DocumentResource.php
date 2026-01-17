<?php

namespace Starter\ServerDocumentation\Filament\Admin\Resources;

use App\Traits\Filament\CanModifyForm;
use App\Traits\Filament\CanModifyTable;
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
use Filament\Tables\Columns\IconColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Filters\TernaryFilter;
use Filament\Tables\Filters\TrashedFilter;
use Filament\Tables\Table;
use Illuminate\Support\HtmlString;
use Illuminate\Support\Str;
use Starter\ServerDocumentation\Filament\Admin\Resources\DocumentResource\Pages;
use Starter\ServerDocumentation\Filament\Admin\Resources\DocumentResource\RelationManagers;
use Starter\ServerDocumentation\Models\Document;

class DocumentResource extends Resource
{
    use CanModifyForm;
    use CanModifyTable;

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
        return trans('server-documentation::strings.navigation.documents');
    }

    public static function getModelLabel(): string
    {
        return trans('server-documentation::strings.document.singular', [], 'en') !== 'server-documentation::strings.document.singular'
            ? trans('server-documentation::strings.document.singular')
            : 'Document';
    }

    public static function getPluralModelLabel(): string
    {
        return trans('server-documentation::strings.document.plural', [], 'en') !== 'server-documentation::strings.document.plural'
            ? trans('server-documentation::strings.document.plural')
            : 'Documents';
    }

    public static function getNavigationGroup(): ?string
    {
        return trans('server-documentation::strings.navigation.group', [], 'en') !== 'server-documentation::strings.navigation.group'
            ? trans('server-documentation::strings.navigation.group')
            : 'Content';
    }

    public static function getNavigationBadge(): ?string
    {
        return (string) static::getEloquentQuery()->count() ?: null;
    }

    public static function defaultForm(Schema $schema): Schema
    {
        return $schema
            ->columns(1)
            ->components([
                Section::make(trans('server-documentation::strings.form.details_section'))->schema([
                    TextInput::make('title')
                        ->label(trans('server-documentation::strings.document.title'))
                        ->required()
                        ->maxLength(255)
                        ->live(onBlur: true)
                        ->afterStateUpdated(fn ($state, $set, ?Document $record) =>
                            $record === null ? $set('slug', Str::slug($state)) : null
                        ),

                    TextInput::make('slug')
                        ->label(trans('server-documentation::strings.document.slug'))
                        ->required()
                        ->maxLength(255)
                        ->unique(ignoreRecord: true)
                        ->rules(['alpha_dash']),

                    Select::make('type')
                        ->label(trans('server-documentation::strings.document.type'))
                        ->options([
                            'host_admin' => trans('server-documentation::strings.types.host_admin') . ' (' . trans('server-documentation::strings.types.host_admin_description') . ')',
                            'server_admin' => trans('server-documentation::strings.types.server_admin') . ' (' . trans('server-documentation::strings.types.server_admin_description') . ')',
                            'server_mod' => trans('server-documentation::strings.types.server_mod') . ' (' . trans('server-documentation::strings.types.server_mod_description') . ')',
                            'player' => trans('server-documentation::strings.types.player') . ' (' . trans('server-documentation::strings.types.player_description') . ')',
                        ])
                        ->default('player')
                        ->required()
                        ->native(false),

                    Toggle::make('is_global')
                        ->label(trans('server-documentation::strings.labels.all_servers'))
                        ->helperText(trans('server-documentation::strings.labels.all_servers_helper')),

                    Toggle::make('is_published')
                        ->label(trans('server-documentation::strings.document.is_published'))
                        ->default(true)
                        ->helperText(trans('server-documentation::strings.labels.published_helper')),

                    TextInput::make('sort_order')
                        ->label(trans('server-documentation::strings.document.sort_order'))
                        ->numeric()
                        ->default(0)
                        ->helperText(trans('server-documentation::strings.labels.sort_order_helper')),
                ])->columns(3)->columnSpanFull(),

                Section::make(trans('server-documentation::strings.document.content'))->schema([
                    RichEditor::make('content')
                        ->label('')
                        ->required()
                        ->extraAttributes(['style' => 'min-height: 400px;'])
                        ->columnSpanFull(),
                ])->columnSpanFull(),

                Section::make(trans('server-documentation::strings.permission_guide.title'))
                    ->description(trans('server-documentation::strings.permission_guide.description'))
                    ->collapsed()
                    ->schema([
                        Placeholder::make('help')
                            ->label('')
                            ->content(new HtmlString('
                                <div class="prose prose-sm dark:prose-invert max-w-none">
                                    <p class="text-sm text-gray-500 dark:text-gray-400 mb-4">
                                        <strong>' . trans('server-documentation::strings.document.type') . '</strong> ' . trans('server-documentation::strings.permission_guide.type_controls') . '
                                        <strong>' . trans('server-documentation::strings.labels.all_servers') . '</strong> ' . trans('server-documentation::strings.permission_guide.all_servers_controls') . '
                                    </p>

                                    <table class="min-w-full text-sm">
                                        <thead>
                                            <tr class="border-b border-gray-200 dark:border-gray-700">
                                                <th class="text-left py-2 pr-4 font-medium">' . trans('server-documentation::strings.document.type') . '</th>
                                                <th class="text-left py-2 pr-4 font-medium">' . trans('server-documentation::strings.permission_guide.who_can_see') . '</th>
                                            </tr>
                                        </thead>
                                        <tbody class="divide-y divide-gray-100 dark:divide-gray-800">
                                            <tr>
                                                <td class="py-2 pr-4"><span class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-md bg-danger-50 text-danger-700 dark:bg-danger-900/50 dark:text-danger-400">' . trans('server-documentation::strings.types.host_admin') . '</span></td>
                                                <td class="py-2 text-gray-600 dark:text-gray-300">' . trans('server-documentation::strings.types.host_admin_description') . '</td>
                                            </tr>
                                            <tr>
                                                <td class="py-2 pr-4"><span class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-md bg-warning-50 text-warning-700 dark:bg-warning-900/50 dark:text-warning-400">' . trans('server-documentation::strings.types.server_admin') . '</span></td>
                                                <td class="py-2 text-gray-600 dark:text-gray-300">' . trans('server-documentation::strings.types.server_admin_description') . '</td>
                                            </tr>
                                            <tr>
                                                <td class="py-2 pr-4"><span class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-md bg-info-50 text-info-700 dark:bg-info-900/50 dark:text-info-400">' . trans('server-documentation::strings.types.server_mod') . '</span></td>
                                                <td class="py-2 text-gray-600 dark:text-gray-300">' . trans('server-documentation::strings.types.server_mod_description') . '</td>
                                            </tr>
                                            <tr>
                                                <td class="py-2 pr-4"><span class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-md bg-success-50 text-success-700 dark:bg-success-900/50 dark:text-success-400">' . trans('server-documentation::strings.types.player') . '</span></td>
                                                <td class="py-2 text-gray-600 dark:text-gray-300">' . trans('server-documentation::strings.types.player_description') . '</td>
                                            </tr>
                                        </tbody>
                                    </table>

                                    <p class="text-xs text-gray-400 dark:text-gray-500 mt-4">
                                        ' . trans('server-documentation::strings.permission_guide.hierarchy_note') . '
                                    </p>
                                </div>
                            ')),
                    ])->columnSpanFull(),
            ]);
    }

    public static function defaultTable(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('title')
                    ->label(trans('server-documentation::strings.document.title'))
                    ->searchable()
                    ->sortable()
                    ->description(fn (Document $record) => Str::limit(strip_tags($record->content), 50)),

                TextColumn::make('type')
                    ->label(trans('server-documentation::strings.document.type'))
                    ->badge()
                    ->formatStateUsing(fn (string $state): string => match ($state) {
                        'host_admin' => trans('server-documentation::strings.types.host_admin'),
                        'server_admin', 'admin' => trans('server-documentation::strings.types.server_admin'),
                        'server_mod' => trans('server-documentation::strings.types.server_mod'),
                        'player' => trans('server-documentation::strings.types.player'),
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
                    ->label(trans('server-documentation::strings.document.is_global'))
                    ->trueIcon('tabler-world')
                    ->falseIcon('tabler-world-off'),

                IconColumn::make('is_published')
                    ->boolean()
                    ->label(trans('server-documentation::strings.document.is_published')),

                TextColumn::make('servers_count')
                    ->counts('servers')
                    ->label(trans('server-documentation::strings.table.servers'))
                    ->badge(),

                TextColumn::make('author.username')
                    ->label(trans('server-documentation::strings.document.author'))
                    ->toggleable(isToggledHiddenByDefault: true),

                TextColumn::make('updated_at')
                    ->label(trans('server-documentation::strings.table.updated_at'))
                    ->dateTime()
                    ->sortable()
                    ->toggleable(),
            ])
            ->filters([
                SelectFilter::make('type')
                    ->label(trans('server-documentation::strings.document.type'))
                    ->options([
                        'host_admin' => trans('server-documentation::strings.types.host_admin'),
                        'server_admin' => trans('server-documentation::strings.types.server_admin'),
                        'server_mod' => trans('server-documentation::strings.types.server_mod'),
                        'player' => trans('server-documentation::strings.types.player'),
                    ]),

                TernaryFilter::make('is_global')
                    ->label(trans('server-documentation::strings.document.is_global')),

                TernaryFilter::make('is_published')
                    ->label(trans('server-documentation::strings.document.is_published')),

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
            ->emptyStateHeading(trans('server-documentation::strings.table.empty_heading'))
            ->emptyStateDescription(trans('server-documentation::strings.table.empty_description'));
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
            'versions' => Pages\ViewDocumentVersions::route('/{record}/versions'),
        ];
    }
}
