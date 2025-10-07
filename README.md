# v_blogger
## About
v_bogger is a blogging platform created using the V programming language and HTMX for additional interactivity. 
This software is currently in *alpha* and a number of features are unsupported. See the roadmap below. Once the current roadmap features and the known security and reliability improvements are complete, the project will be moved into *beta* for testing.
Please see the [releases page](https://github.com/Meeds122/v_blogger/releases) for the latest pre-compiled versions. Instructions for compiling this project are further on in this document. 

## Status
### Supported Features
Currently Supported Features
- Light mode / dark mode
- In-app initial setup
- HTML Markup
- Create new posts
- Delete posts
- Submit comments
- Delete comments
- Administrator management
- Administrator password change
- Drafts
- Editing
- Backup and Restore (export and import)
- Image handling

### Improvements In Progress
Security and Reliability Improvements
- [DONE] Generated session secrets
- [DONE] Index guards
- [DONE] Absolute static resource paths
- [DONE] Fix username disclosure via timing
- [TODO] MFA

### Future Improvements
Eventual features
- MFA Improvements
  - QR Codes for MFA
  - Update MFA method
  - Other MFA options
- More convenient navigation
  - Admin header links on drafts
  - Front page pagination
- Additional responsiveness on long requests
  - Login
  - Uploads
- Post search
- SEO improvements
- Markdown support! Maybe? 


## Run from source
1. [Install the V programming language.](https://docs.vlang.io/installing-v-from-source.html) Make sure you [symlink](https://github.com/vlang/v/blob/master/README.md#symlinking) the V programming language to make it available on the PATH.
2. Install the required depenencies.
  1. `$ v install sqlite`
  2. `$ v install Meeds122.totp`
3. Clone this github repository `git clone https://github.com/Meeds122/v_blogger.git`
4. Move into the new directory `cd v_blogger`
5. Compile with `v -prod -o v_blogger .` This will take some time as production V compilation takes time. You can compile in dev mode using `v .` which is much faster if you are just testing. `v run .` will compile and run the program in dev mode all at once.
6. Run the newly created v_blogger executable.
7.  Visit your new blog at [http://localhost:8080](http://localhost:8080)


## About publishing to the internet
This app is not configured to be available on the internet. While I made some good decisions (I think!) regarding the security of the app, V's veb framework does not support TLS encryption which is a must on the modern web. Use a reverse proxy such as Apache, NGINX, Caddy, or Kamal to handle HTTPS translation. Certain higher-traffic sites may wish to move the /static .css and .js files to the reverse proxy or another host for better compression, caching, and performance. Eventually, I would like to make a docker image that includes the reverse proxy for easy production deployment, but that project is beyond today's beta version. 


## AI Statement
This application utilized AI in creating HTML and CSS mockups for the web pages.

## Author's Notes
This application was created both to serve my own needs for a blogging engine and to learn more about the V language and HTMX web programming.