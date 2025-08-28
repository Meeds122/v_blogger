module main

// All imports are in stdlib except sqlite.
// veb imports
import veb
import net.http { Cookie, SameSite }
import sqlite // V's SQLite wrapper. $ v install sqlite
// utilities
import time
import strconv
import toml
import os
// password hashing
import crypto.bcrypt
// sessions
import crypto.hmac
import crypto.sha512
import rand
import encoding.base64

// Context is not shared between requests. It manages the request session
pub struct Context {
    veb.Context
pub mut:
	is_admin bool
	session_validated bool
	session Session
}

// App is shared by all requests. It manages the veb server in whole. 
pub struct App {
	veb.StaticHandler
	veb.Middleware[Context]
pub:
	port			int
	config_file		string
	article_db		sqlite.DB
	admin_db		sqlite.DB
	hash_cost		int
pub mut:
	needs_setup		bool 
	tab_title		string
	title			string		// true if we need to first time run (i.e. config.toml not exist.)
	session_expire 	int 		// Session expiration in seconds. 
	session_secret	string
	sessions 		[]Session
}

fn main() {
    mut app := &App{
		port:			8080
		config_file: 	'config.toml'
		article_db:		sqlite.connect('articles.db') or { panic(err) }
		admin_db:		sqlite.connect('admins.db') or { panic(err) }
		hash_cost:		14		// How long to reset password / create new user / sign on. Min 10. Rec 12.
		sessions:		[]Session{}
    }

	// read config and set needs_setup
	if !os.exists(app.config_file){
		app.needs_setup = true
		app.use(handler: app.setup_blog)
	}
	else {
		app.needs_setup = false
		doc := toml.parse_file(app.config_file) or { panic(err) }
		app.tab_title = doc.value('tab_title').string()
		app.title = doc.value('title').string()
		app.session_expire = strconv.atoi(doc.value('session_expire').string()) or { panic(err) }
		app.session_secret = doc.value('session_secret').string()
	}

	sql app.article_db {
        create table Post
		create table Comment
    } or { panic(err) }

	sql app.admin_db {
		create table Admin
	} or { panic(err) }

	app.handle_static('static', true) or { panic(err) }

	app.use(handler: app.check_login)
    
    veb.run[App, Context](mut app, app.port)
}

// fyi, V has a live reload feature for veb dev: $ v -d veb_livereload watch run .
// When deploying to prod: $ v -prod -o v_blogger .

// TODOs:
// 		1. Draft handling in manage posts and new post
// 		2. Edit functions in manage posts
// 		3. Import Database
// 		4. Upload and delete images
//		5. Config update and server control? Reset to default?
// 		6. Fix is_admin middleware to be immutable
// 			- Move old session cleanup to login (should be infrequent.)

// IDEAs: 
// 		1. Use V's template engine to insert the css and js if performance with the static handler becomes a bottleneck
// 			- How to measure tho? Also, even though static handler is 1/2 as performant as template, it is very fast
//		2. Caddy for HTTPS reverse proxy? NGINX and use it to server statics too? Set cache times on htmx and css? 

// ------------
// -- Models --
// -----------

pub struct Post {
pub:
	post_id 	int		@[primary; unique; serial]
	created		i64
pub mut:
	draft		bool
	updated		i64
	title		string
	summary		string
	content		string
}

pub struct Comment {
pub:
	comment_id	int		@[primary; unique; serial]
	submitted	i64
	name		string
	email 		string
	message		string
}

pub struct Admin {
	user_id			int 	@[primary; unique; serial]
	username 		string
	password_hash	string
}

pub struct Session {
pub:
	user_id		int
	token		string
	expiration	i64		// Epoch timestamp of when expire. 
}

// ----------------
// -- Middleware --
// ----------------

pub fn (app &App) setup_blog (mut ctx Context) bool {
	if !app.needs_setup {
		return true
	}
	else if ctx.Context.req.url != '/initialconfig' {
		// Here be runtime errors
		if ctx.Context.req.url.len > 5 {
			if (ctx.Context.req.url[ctx.Context.req.url.len-3..ctx.Context.req.url.len] != '.js') || (ctx.Context.req.url[ctx.Context.req.url.len-4..ctx.Context.req.url.len] != '.css'){
				// Need to exlude .js and .css files from the universal redirect.
				return true
			}
		}
		// Not any previous case, fall down to redir.
		ctx.redirect('/initialconfig')
		return false
	}
	else {
		return true
	}
}

pub fn (mut app App) check_login (mut ctx Context) bool {
	// No token cookie, no access
	cookie_val := ctx.get_cookie('token') or { 
		ctx.is_admin = false
		ctx.session_validated = false
		return true
	}
	// Yes token cookie, not session is expired.
	for i in 0..app.sessions.len {
		if (cookie_val == app.sessions[i].token) && !Session.is_expired(app.sessions[i]) {
			ctx.session = app.sessions[i]
			ctx.is_admin = true
			ctx.session_validated = true
			return true
		}
		// clean up old expired sessions otherwise app.sessions can grow without bound.
		else if Session.is_expired(app.sessions[i]){
			app.sessions.delete(i)
		}
	}
	// The token cookie exists but is not valid
	ctx.set_cookie(http.Cookie{
				name: 'token'
				value: ''
				path: '/'
				same_site: SameSite.same_site_strict_mode
				http_only: true
				max_age: -1 // Delete cookie
    		})
	
	ctx.is_admin = false
	return true
}

// -----------------------------
// -- Public Template Service --
// -----------------------------

pub fn (app &App) index(mut ctx Context) veb.Result {
	title := app.title
	tab_title := app.tab_title
	return $veb.html()
}

// -------------------
// -- Public Routes -- 
// -------------------

// hitting this endpoint with no get parameters yields all posts
// including ?from=&to= will yield a set of those posts.
@['/posts'; get]
pub fn (app &App) all_posts (mut ctx Context) veb.Result {

	mut posts := sql app.article_db {
		select from Post where draft == false
    } or { panic(err) }

	// Early exit if no content
	if posts.len == 0 {
		return ctx.html('<p>No Content</p>')
	}

	// Sort by latest e.g. created high to low
	posts.sort(a.created > b.created)

	mut content := ''

	// Create set of post stubs if requested
	if ('from' in ctx.query) && ('to' in ctx.query) {
		
		from := strconv.atoi(ctx.query['from']) or { return ctx.request_error('Error: Requires from= value') }
		to := strconv.atoi(ctx.query['to']) or { return ctx.request_error('Error: Requires to= value') }

		// Unfortunately, there is no promise that post_id is going to be contiguous.
		mut counter := 0 // Also, count from one because the ORM's auto incrementer does that for post_id
		for post in posts {
			if (counter >= from) && (counter < to){
				content += make_post_stub(post.post_id, 
										post.title, 
										time.unix(post.created).strftime('%F'),
										post.summary )
			}
			counter += 1
		}
		if content.len == 0 {
			return ctx.request_error('Error: Invalid range')
		}
	}
	else {
		// Otherwise, create full set of post stubs. 
		for post in posts {
			content += make_post_stub(post.post_id, 
									post.title, 
									time.unix(post.created).strftime('%F'),
									post.summary )
		}
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
	// V's template engine doesn't seem to be able to disable the html escaping. Need to use htmx.
	// It is still way faster than the static handler. 
	// post_content := post[0].content
	str_created := time.unix(post[0].created).strftime('%F')
	str_modified := time.unix(post[0].updated).strftime('%F')
	draft := post[0].draft

	mut str_draft := ''
	if draft {
		str_draft = 'DRAFT - '
	}

	// Dont let people get drafts from the /post endpoint unless administrator
	if (draft == true) && (ctx.is_admin == false) {
		return ctx.redirect('/', typ: .see_other)
	}
	else {
		return $veb.html()
	}
}

// Need to use an HTMX query to load body html if we are formatting via it. 
// V automatically escapes HTML which is great for security, but not great here
// since only admins can post new articles with HTML rendered.
@['/content/:id'; get]
pub fn (app &App) get_content (mut ctx Context, id int) veb.Result {

	post := sql app.article_db {
		select from Post where post_id == id limit 1
    } or { panic(err) }

	// Dont let people get drafts from the /post endpoint unless administrator
	draft := post[0].draft
	if (draft == true) && (ctx.is_admin == false) {
		return ctx.not_found()
	}
	else {
		return ctx.html(post[0].content)
	}
}

@['/comment'; post]
pub fn (app &App) comment(mut ctx Context) veb.Result {
	error_message := '<p>Submission Failure</p>'

	// Let's make sure the form submission is complete. 
	if ('name' !in ctx.form) || ('email' !in ctx.form) || ('message' !in ctx.form) {
		return ctx.request_error(error_message)
	}
	// Let's make sure no fields are blank
	match false {
        ctx.form['name'].len > 0  { return ctx.html(error_message) }
        ctx.form['email'].len > 0     { return ctx.html(error_message) }
        ctx.form['message'].len > 0  { return ctx.html(error_message) }
        else {}
    }

	new_comment := Comment {
		submitted: time.now().unix()
		name: johanns_maw(ctx.form['name'])
		email: johanns_maw(ctx.form['email'])
		message: johanns_maw(ctx.form['message'])
	}

	sql app.article_db {
		insert new_comment into Comment
    } or { panic(err) }

	return ctx.html('<p>Submitted!</p>')
}

@['/login'; post]
pub fn (mut app App) login(mut ctx Context) veb.Result {
	in_username := ctx.form['username']
	in_password := ctx.form['password']

	login_failure := 'Login Failure'

	user := sql app.admin_db {
		select from Admin where username == in_username limit 1
	} or { panic(err) }

	// Might be an info leak via timing here
	// Also, need to check len vs max_len because len > max_len == easy DoS
	if user.len != 1 {
		return ctx.html(login_failure)
	}
	else{
		// Error for standard case handling WTF is this interface.
		bcrypt.compare_hash_and_password(in_password.bytes(), user[0].password_hash.bytes()) or { 
			// Some failure of some kind. Probably not match
			return ctx.html(login_failure)
		}
		// No failure, probably does match, go admin
		session := Session.new(user[0].user_id, app.session_secret, app.session_expire) or { 
			return ctx.html(login_failure)
		 }
		app.sessions << session
		ctx.set_cookie(http.Cookie{
				name: 'token'
				value: session.token
				path: '/'
				// secure: true // Requires HTTPS. Dunno how that would work with a reverse proxy
				same_site: SameSite.same_site_strict_mode
				http_only: true
				// expires: time.unix(time.now().unix() + app.session_expire) // BUG? doesn't seem to work as documented. 
    		})
		return ctx.html('<script>document.location="/admin";</script>')

	}
	return ctx.html(login_failure)
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
		draft: false
		created: time.now().unix()
		updated: time.now().unix()
		title: ctx.form['title']
		summary: ctx.form['summary']
		content: ctx.form['content']
	}

	post_id := sql app.article_db {
		insert new_post into Post
    } or { panic(err) }

	return ctx.html('<button onclick="location.href = \'/post/${post_id}\';">View Post</button><p style="text-align: center;">Success!</p>')
}

@['/export'; get; post]
pub fn (app &App) export(mut ctx Context) veb.Result {
	// Admin Gate
	if !ctx.is_admin {
		return ctx.redirect('/', typ: .see_other)
	}
	
	if ctx.req.method == .get {
		title := app.title
		tab_title := app.tab_title
		return $veb.html()
	}
	else if ctx.req.method == .post {
		ctx.set_content_type('application/octet-stream')
		ctx.set_custom_header('Content-Disposition', 'attachment; filename="articles.db"') or {panic(err)}
		return ctx.file('articles.db')
	}
	else {
		return ctx.request_error('Error: unknown verb')
	}
}

@['/comments/all'; get]
pub fn (app &App) manage_all_comments(mut ctx Context) veb.Result{
	// Admin Gate
	if !ctx.is_admin {
		return ctx.redirect('/', typ: .see_other)
	}

	mut comments := sql app.article_db {
		select from Comment
	} or { panic(err) }

	if comments.len == 0 {
		return ctx.html('<p>No Comments</p>')
	}

	// Sort into newest comment first.
	comments.sort(a.submitted > b.submitted)

	mut content := ''
	for comment in comments {
		content += make_comment_stub(
			comment.comment_id,
			comment.name,
			comment.email,
			comment.message,
			time.unix(comment.submitted).strftime('%F %I:%M %p')
		)
	}

	return ctx.html(content)
}

@['/comment/:id'; delete]
pub fn (app &App) manage_comment(mut ctx Context, id int) veb.Result {
	// Admin Gate
	if !ctx.is_admin {
		return ctx.redirect('/', typ: .see_other)
	}

	sql app.article_db {
		delete from Comment where comment_id == id
	} or { panic(err) }

	return ctx.html('<p>Deleted</p>')
}

@['/managepost/:id'; delete]
pub fn (app &App) delete_post(mut ctx Context, id int) veb.Result {
	// Admin Gate
	if !ctx.is_admin {
		return ctx.redirect('/', typ: .see_other)
	}

	sql app.article_db {
		delete from Post where post_id == id
	} or { panic(err) }

	return ctx.html('<p>Deleted</p>')
}

// TODO
@['/managepost/draft/:id'; put]
pub fn (app &App) swap_draft(mut ctx Context, id int) veb.Result {
	// Admin Gate
	if !ctx.is_admin {
		return ctx.redirect('/', typ: .see_other)
	}

	return ctx.no_content()
}

// TODO
@['/managepost/:id'; put]
pub fn (app &App) update_post(mut ctx Context, id int) veb.Result {
	// Admin Gate
	if !ctx.is_admin {
		return ctx.redirect('/', typ: .see_other)
	}

	return ctx.no_content()
}

// TODO
@['/managepost/:id'; get]
pub fn (app &App) update_post_page(mut ctx Context, id int) veb.Result {
	// Admin Gate
	if !ctx.is_admin {
		return ctx.redirect('/', typ: .see_other)
	}

	return ctx.no_content()
}

@['/manageposts/all'; get]
pub fn (app &App) manage_all_posts (mut ctx Context) veb.Result{
	// Admin Gate
	if !ctx.is_admin {
		return ctx.redirect('/', typ: .see_other)
	}

	mut posts := sql app.article_db {
		select from Post
	} or { panic(err) }

	if posts.len == 0 {
		return ctx.html('<p>No Posts</p>')
	}

	// Sort into newest comment first.
	posts.sort(a.created > b.created)

	mut content := ''
	for post in posts {
		mut title := ''
		if post.draft {
			title = 'DRAFT - '
		}
		title += post.title
		content += make_managepost_stub(
			post.post_id,
			title
		)
	}

	return ctx.html(content)
}

@['/manageadmins/password/:id'; patch]
pub fn (app &App) update_password (mut ctx Context, id int) veb.Result {
	// Admin Gate
	if !ctx.is_admin {
		return ctx.redirect('/', typ: .see_other)
	}

	if ctx.session.user_id != id {
		return ctx.html('<p>Unable to update another existing admin\'s password')
	}

	// verify provided passwords match
	if !(ctx.form['new_password'] == ctx.form['confirm_password']){
		return ctx.html('<p>Server Response: Passwords do not match</p>')
	}

	// verify existing password
	// I can't seem to find if ORM has a column select
	current_password := sql app.admin_db {
		select from Admin where user_id == id limit 1
	} or { panic(err) }
	bcrypt.compare_hash_and_password(ctx.form['current_password'].bytes(), current_password[0].password_hash.bytes()) or { 
		// Some failure of some kind. Probably not match
		return ctx.html('<p>Server Response: Current pasword match failure.</p>')
	}

	new_hash := bcrypt.generate_from_password(ctx.form['new_password'].bytes(), app.hash_cost) or { 
		panic(err)
	 }

	sql app.admin_db {
		update Admin set password_hash = new_hash where user_id == id
	} or { panic(err) }

	return ctx.html('<p>Password Updated</p>')
}

@['/manageadmins'; post]
pub fn (app &App) new_user (mut ctx Context) veb.Result {
	// Admin Gate
	if !ctx.is_admin {
		return ctx.redirect('/', typ: .see_other)
	}

	users := sql app.admin_db {
		select from Admin
	} or { panic(err) }

	for user in users{
		if user.username == ctx.form['username']{
			return ctx.html('<p>Account already exists</p>')
		}
	}

	new_hash := bcrypt.generate_from_password(ctx.form['password'].bytes(), app.hash_cost) or { 
		panic(err)
	}

	new_user := Admin {
		username: ctx.form['username']
		password_hash: new_hash
	}

	sql app.admin_db {
		insert new_user into Admin
	} or { panic(err) }

	return ctx.html('<p>Account Created</p>')
}

// TODO
@['/manageadmin/delete/:id'; delete]
pub fn (app &App) delete_user (mut ctx Context, id int) veb.Result {
	// Admin Gate
	if !ctx.is_admin {
		return ctx.redirect('/', typ: .see_other)
	}

	if ctx.session.user_id == id {
		return ctx.html('<p>Error: Cannot delete self</p>')
	}

	sql app.admin_db {
		delete from Admin where user_id == id
	} or { panic(err) }

	return ctx.html('<p>Account Deleted</p>')
}

// TODO
@['/manageadmins/all'; get]
pub fn (app &App) all_users (mut ctx Context, id int) veb.Result {
	// Admin Gate
	if !ctx.is_admin {
		return ctx.redirect('/', typ: .see_other)
	}

	users := sql app.admin_db {
		select from Admin
	} or { panic(err) }

	mut content := ''
	for user in users {
		if user.user_id == ctx.session.user_id {
			continue
		}
		content += make_users_stub(user.user_id, user.username)
	}
	if content.len == 0 {
		content = '<p>No other user accounts available to manage.</p>'
	}

	return ctx.html(content)
}

@['/initialconfig'; post]
pub fn (mut app App) configure_app(mut ctx Context) veb.Result {
	// Setup Gate
	if !app.needs_setup {
		return ctx.redirect('/', typ: .see_other)
	}

	// Pull in form data
	app.title = ctx.form['title']
	app.tab_title = ctx.form['tab_title']
	app.session_expire = 60 * strconv.atoi(ctx.form['session_timeout']) or { panic(err) }// comes in as minutes, is stored as seconds.
	app.session_secret = ctx.form['session_secret']
	username := ctx.form['initial_username']
	password := ctx.form['initial_password']

	// Create TOML config.
	// file ops
	mut f := os.create(app.config_file) or { panic(err) }
	f.writeln('tab_title = "${app.tab_title}"') or { panic(err) }
	f.writeln('title = "${app.title}"') or { panic(err) }
	f.writeln('session_expire = "${app.session_expire}"') or { panic(err) }
	f.writeln('session_secret = "${app.session_secret}"') or { panic(err) }
	f.close()

	// Create admin account
	new_hash := bcrypt.generate_from_password(password.bytes(), app.hash_cost) or { 
		panic(err)
	}
	new_user := Admin {
		username: username
		password_hash: new_hash
	}
	sql app.admin_db {
		insert new_user into Admin
	} or { panic(err) }

	// Set needs_setup to false and redir
	app.needs_setup = false

	return ctx.redirect('/', typ: .see_other)
}

// ------------------------------
// -- Private Template Service --
// ------------------------------ 

@['/initialconfig'; get]
pub fn (app &App) initialconfig(mut ctx Context) veb.Result {
	// Setup Gate
	if !app.needs_setup {
		return ctx.redirect('/', typ: .see_other)
	}

	title := app.title
	tab_title := app.tab_title
	return $veb.html()
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

// TODO
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
	
	current_user_id := ctx.session.user_id
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

// TODO
pub fn (app &App) uploadimage(mut ctx Context) veb.Result {
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

fn make_comment_stub (c_id int, c_name string, c_email string, c_comment string, c_date string) string {
	return $tmpl('templates/comment_stub.html')
}

fn make_managepost_stub (post_id int, post_title string) string {
	return $tmpl('templates/manageposts_stub.html')
}

fn make_users_stub (id int, username string) string {
	return $tmpl('templates/admin_stub.html')
}

// This function reminds me of python string maipulation and now I feel gross. 
fn johanns_maw (text string) string {
	banned_chars := {
		'&': '&amp'
		'<': '&lt'
		'>': '&gt'
		'"': '&quot'
		"'": '&#x27'
	}

	mut return_text := ''

	for i in 0..text.len {
		if text[i].ascii_str() in banned_chars.keys() {
			return_text += banned_chars[text[i].ascii_str()]
		}
		else {
			return_text += text[i].ascii_str()
		}
	}
	return return_text
}

fn Session.new_token(session_secret string) !string {
	// crypto func sha512.sum512(f_bytes).hex()	
	return base64.encode(
					hmac.new(
							session_secret.bytes(), 
							rand.bytes(128) or {return err}, 
							sha512.sum512, 
							128)
						)
}

fn Session.new(user_id int, session_secret string, ttl i64) !Session {
	return Session {
		user_id: user_id
		token: Session.new_token(session_secret) or { panic(err) }
		expiration: time.now().unix() + ttl
	}
}

fn Session.is_expired(session Session) bool {
	now := time.now().unix()
	match true {
		now > session.expiration { return true }
		now == session.expiration { return true }
		now < session.expiration { return false }
		else { return true } // better safe than sorry
	}
}