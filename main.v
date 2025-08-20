module main

import veb
import sqlite // V's SQLite wrapper. $ v install sqlite

import time

// Context is not shared between requests. It manages the request session
pub struct Context {
    veb.Context
pub mut:
	is_admin bool
}

// App is shared by all requests. It manages the veb server in whole. 
pub struct App {
	veb.StaticHandler
	veb.Middleware[Context]
pub:
	port		int
	article_db	sqlite.DB
pub mut:
	tab_title	string
	title		string
}

fn main() {
    mut app := &App{
		port:			8080
		article_db:		sqlite.connect('articles.db') or { panic(err) }
		tab_title:		'V_Blogger Title'
		title:			'V_Blogger'
    }

	sql app.article_db {
        create table Post
    } or { panic(err) }

	app.handle_static('static', true) or { panic(err) }

	app.use(handler: app.check_login)
    
    veb.run[App, Context](mut app, app.port)
}

// fyi, V has a live reload feature for veb dev: $ v -d veb_livereload watch run .
// When deploying to prod: $ v -prod -o v_blogger .

// TODOs:
// 		1. Create Login, Sessions, auth validation middle ware
// 			- Create and validate sessions
//			- Set session cookie on long
// 			- Read session from cookie on middleware hit and validate
// 			- setup secure.db
// 			- setup account registration
// 			- setup login checking

// IDEAs: 
// 		1. Use V's template engine to insert the css and js if performance with the static handler becomes a bottleneck
// 			- How to measure tho? Also, even though static handler is 1/2 as performant as template, it is very fast

// ------------
// -- Models --
// ------------

pub struct Post {
pub:
	post_id 	int		@[primary; unique; serial]
	created		i64
pub mut:
	updated		i64
	title		string
	summary		string
	content		string
}

// ----------------
// -- Middleware --
// ----------------
pub fn (app &App) check_login (mut ctx Context) bool {
    ctx.is_admin = true
	return true
}

// -------------------
// -- Public Routes -- 
// -------------------

pub fn (app &App) index(mut ctx Context) veb.Result {
	title := app.title
	tab_title := app.tab_title
	return $veb.html()
}

@['/posts'; get]
pub fn (app &App) all_posts (mut ctx Context) veb.Result {

	mut posts := sql app.article_db {
		select from Post
    } or { panic(err) }

	// Early exit if no content
	if posts.len == 0 {
		return ctx.html('<p>No Content</p>')
	}

	// Sort by latest e.g. created high to low
	posts.sort(a.created > b.created)

	mut content := ''

	for post in posts {
		content += make_post_stub(post.post_id, 
								post.title, 
								time.unix(post.created).strftime('%F'),
								post.summary )
	}

	return ctx.html(content)
}

@['/post/:id'; get]
pub fn (app &App) post(mut ctx Context, id int) veb.Result {
	// post_id used in template. Probably best to replace with a title or generic. 
	title := app.title
	tab_title := app.tab_title

	post := sql app.article_db {
		select from Post where post_id == id limit 1
    } or { panic(err) }

	post_title := post[0].title
	post_content := post[0].content
	str_created := time.unix(post[0].created).strftime('%F')
	str_modified := time.unix(post[0].updated).strftime('%F')

	return $veb.html()
}

@['/login'; post]
pub fn (app &App) login(mut ctx Context) veb.Result {
	username := ctx.form['username']
	password := ctx.form['password']
	if (username == 'admin') && (password == 'admin'){
		return ctx.redirect('/admin', typ: .see_other)
	}
	else {
		return ctx.redirect('/', typ: .see_other)
	}
}

// --------------------
// -- Private Routes --
// --------------------

@['/publish'; post]
pub fn (app &App) publish(mut ctx Context) veb.Result {
	// Admin Gate
	if !ctx.is_admin {
		return ctx.redirect('/', typ: .see_other)
	}
	new_post := Post {
		created: time.now().unix()
		updated: time.now().unix()
		title: ctx.form['title']
		summary: ctx.form['summary']
		content: ctx.form['content']
	}

	sql app.article_db {
		insert new_post into Post
    } or { panic(err) }

	return ctx.html('Post Succesful')
}

pub fn (app &App) admin(mut ctx Context) veb.Result {
	// Admin Gate
	if !ctx.is_admin {
		return ctx.redirect('/', typ: .see_other)
	}

	title := app.title
	tab_title := app.tab_title
	return $veb.html()
}

pub fn (app &App) export(mut ctx Context) veb.Result {
	// Admin Gate
	if !ctx.is_admin {
		return ctx.redirect('/', typ: .see_other)
	}
	
	title := app.title
	tab_title := app.tab_title
	return $veb.html()
}

pub fn (app &App) import(mut ctx Context) veb.Result {
	// Admin Gate
	if !ctx.is_admin {
		return ctx.redirect('/', typ: .see_other)
	}
	
	title := app.title
	tab_title := app.tab_title
	return $veb.html()
}

pub fn (app &App) manageadmins(mut ctx Context) veb.Result {
	// Admin Gate
	if !ctx.is_admin {
		return ctx.redirect('/', typ: .see_other)
	}
	
	title := app.title
	tab_title := app.tab_title
	return $veb.html()
}

pub fn (app &App) manageposts(mut ctx Context) veb.Result {
	// Admin Gate
	if !ctx.is_admin {
		return ctx.redirect('/', typ: .see_other)
	}
	
	title := app.title
	tab_title := app.tab_title
	return $veb.html()
}

pub fn (app &App) newpost(mut ctx Context) veb.Result {
	// Admin Gate
	if !ctx.is_admin {
		return ctx.redirect('/', typ: .see_other)
	}
	
	title := app.title
	tab_title := app.tab_title
	return $veb.html()
}

pub fn (app &App) comments(mut ctx Context) veb.Result {
	// Admin Gate
	if !ctx.is_admin {
		return ctx.redirect('/', typ: .see_other)
	}
	
	title := app.title
	tab_title := app.tab_title
	return $veb.html()
}

// ----------------------
// -- Helper Functions --
// ----------------------

// Utilize V's template engine to make a post stub for index.
 fn make_post_stub (post_id int, post_title string, post_date string, post_summary string) string {
	return $tmpl('templates/post_stub.html')
 }