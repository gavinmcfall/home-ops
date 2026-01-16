<?php

namespace Starter\ServerDocumentation\Filament\Admin\RelationManagers;

use Filament\Actions\AttachAction;
use Filament\Actions\CreateAction;
use Filament\Actions\DetachAction;
use Filament\Actions\DetachBulkAction;
use Filament\Actions\ViewAction;
use Filament\Forms\Components\RichEditor;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Forms\Components\Toggle;
use Filament\Resources\RelationManagers\RelationManager;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Schema;
use Filament\Tables\Columns\IconColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Support\Str;
use Starter\ServerDocumentation\Filament\Admin\Resources\DocumentResource;
use Starter\ServerDocumentation\Models\Document;

class DocumentsRelationManager extends RelationManager
{
    protected static string $relationship = 'documents';

    protected static ?string $title = 'Documents';

    protected static string|\BackedEnum|null $icon = 'tabler-file-text';

    public function table(Table $table): Table
    {
        return $table
            ->recordTitleAttribute('title')
            ->columns([
                TextColumn::make('title')
                    ->searchable()
                    ->sortable()
                    ->description(fn (Document $record) => Str::limit(strip_tags($record->content), 40)),

                TextColumn::make('type')
                    ->badge()
                    ->color(fn (string $state): string => match ($state) {
                        'admin' => 'danger',
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

                TextColumn::make('pivot.sort_order')
                    ->label('Order')
                    ->sortable(),

                TextColumn::make('updated_at')
                    ->dateTime()
                    ->sortable()
                    ->toggleable(),
            ])
            ->filters([
                SelectFilter::make('type')
                    ->options([
                        'admin' => 'Admin',
                        'player' => 'Player',
                    ]),
            ])
            ->headerActions([
                AttachAction::make()
                    ->preloadRecordSelect()
                    ->form(fn (AttachAction $action): array => [
                        $action->getRecordSelect(),
                        TextInput::make('sort_order')
                            ->numeric()
                            ->default(0)
                            ->helperText('Order this document appears in the list'),
                    ]),
                CreateAction::make()
                    ->mutateFormDataUsing(fn (array $data): array => [
                        ...$data,
                        'author_id' => auth()->id(),
                    ]),
            ])
            ->recordActions([
                ViewAction::make()
                    ->url(fn (Document $record) => DocumentResource::getUrl('edit', ['record' => $record])),
                DetachAction::make(),
            ])
            ->groupedBulkActions([
                DetachBulkAction::make(),
            ])
            ->emptyStateHeading('No documents')
            ->emptyStateDescription('Attach existing documents or create new ones for this server.')
            ->emptyStateIcon('tabler-file-off');
    }
}
