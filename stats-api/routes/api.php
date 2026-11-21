<?php

use App\Http\Controllers\StatsController;
use Illuminate\Support\Facades\Route;

Route::get('/health', fn () => response()->json(['status' => 'ok']));
Route::get('/info', [StatsController::class, 'info']);
Route::get('/stats/info', [StatsController::class, 'info']);
Route::get('/stats', [StatsController::class, 'stats']);
