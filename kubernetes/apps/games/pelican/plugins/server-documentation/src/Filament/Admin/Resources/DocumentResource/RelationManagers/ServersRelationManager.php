<?php

namespace Starter\ServerDocumentation\Filament\Admin\Resources\DocumentResource\RelationManagers;

use Filament\Actions\AttachAction;
use Filament\Actions\DetachAction;
use Filament\Actions\DetachBulkAction;
use Filament\Forms\Components\TextInput;
use Filament\Resources\RelationManagers\RelationManager;
use Filament\Schemas\Schema;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Table;

class ServersRelationManager extends RelationManager
{
    protected static string $relationship = 'servers';

    protected static ?string $title = 'Linked Servers';

    protected static string|\BackedEnum|null $icon = 'tabler-server';

    public function table(Table $table): Table
    {
        return $table
            ->recordTitleAttribute('name')
            ->columns([
                TextColumn::make('name')
                    ->searchable()
                    ->sortable(),

                TextColumn::make('node.name')
                    ->label('Node')
                    ->sortable(),

                TextColumn::make('user.username')
                    ->label('Owner'),

                TextColumn::make('pivot.sort_order')
                    ->label('Sort Order')
                    ->sortable(),
            ])
            ->headerActions([
                AttachAction::make()
                    ->preloadRecordSelect()
                    ->recordSelectSearchColumns(['name', 'uuid', 'uuid_short'])
                    ->form(fn (AttachAction $action): array => [
                        $action->getRecordSelect(),
                        TextInput::make('sort_order')
                            ->numeric()
                            ->default(0)
                            ->helperText('Order this document appears for this server'),
                    ]),
            ])
            ->recordActions([
                DetachAction::make(),
            ])
            ->groupedBulkActions([
                DetachBulkAction::make(),
            ])
            ->emptyStateHeading('No servers linked')
            ->emptyStateDescription('Attach servers to make this document visible on those servers.')
            ->emptyStateIcon('tabler-server-off');
    }
}
