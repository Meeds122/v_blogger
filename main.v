module main

import veb
import sqlite // V's SQLite wrapper. $ v install sqlite

// Context is not shared between requests. It manages the request session
pub struct Context {
    veb.Context
pub mut:
	is_admin bool
}

// App is shared by all requests. It manages the veb server in whole. 
pub struct App {
	veb.StaticHandler
pub:
	port		int
	article_db	sqlite.DB
pub mut:
	tab_title	string
	title		string
}

// fyi, V has a live reload feature for veb dev: $ v -d veb_livereload watch run .
// When deploying to prod: $ v -prod -o v_blogger .

// TODOs:
// 		1. Use the veb asset manager to eliminate the need for the StaticHandler https://modules.vlang.io/veb.assets.html
// 		2. Create Login, Sessions, auth validation middle ware

fn main() {
    mut app := &App{
		port:			8080
		article_db:		sqlite.connect('articles.db') or { panic(err) }
		tab_title:		'CustomCrypto.com - Semiserious Security'
		title:			'CustomCrypto.com'
    }

	sql app.article_db {
        create table Article
    } or { panic(err) }

	app.handle_static('static', true) or { panic(err) }
    
    veb.run[App, Context](mut app, app.port)
}

// ------------
// -- Models --
// ------------

pub struct Article {
pub:
	article_id 	int
	created		i64
pub mut:
	updated		i64
	title		string
	body		string
	summary		string
}

// -------------------
// -- Public Routes -- 
// -------------------

pub fn (app &App) index(mut ctx Context) veb.Result {
	title := app.title
	tab_title := app.tab_title
	return $veb.html()
}

// --------------------
// -- Private Routes --
// --------------------

pub fn (app &App) admin(mut ctx Context) veb.Result {
	title := app.title
	tab_title := app.tab_title
	return $veb.html()
}

pub fn (app &App) export(mut ctx Context) veb.Result {
	title := app.title
	tab_title := app.tab_title
	return $veb.html()
}

pub fn (app &App) import(mut ctx Context) veb.Result {
	title := app.title
	tab_title := app.tab_title
	return $veb.html()
}

pub fn (app &App) manageadmins(mut ctx Context) veb.Result {
	title := app.title
	tab_title := app.tab_title
	return $veb.html()
}

pub fn (app &App) manageposts(mut ctx Context) veb.Result {
	title := app.title
	tab_title := app.tab_title
	return $veb.html()
}

pub fn (app &App) newpost(mut ctx Context) veb.Result {
	title := app.title
	tab_title := app.tab_title
	return $veb.html()
}